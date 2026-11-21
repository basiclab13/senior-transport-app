'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {getStorage}=require('firebase-admin/storage');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {ref,uploadBytes,getBytes,deleteObject,updateMetadata,listAll}=require('firebase/storage');
const {doc,getDoc,setDoc}=require('firebase/firestore');
const sharp=require('sharp');
const {registerWorkPhoto,getWorkPhotos,cleanupWorkPhotos,jpeg,MAX_BYTES}=require('../work-photo-service');
const {registerCatalog}=require('../../tools/fictional_catalog.cjs');
const {operationsCatalog,operationRequest}=require('../../tools/operations_fixture.cjs');
const {confirm}=require('../schedule-service');
const {setStaffAbsence}=require('../staff-absence-service');
if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||
  !['FIRESTORE_EMULATOR_HOST','FIREBASE_STORAGE_EMULATOR_HOST'].every(k=>/^127\.0\.0\.1:\d+$/.test(process.env[k]||'')))throw Error('Loopback Firestore and Storage Emulators required');
test('private Storage work photos: real JPEG, confirmed assignment, atomic completion and recovery',async t=>{
  const projectId='demo-storage-work-photos',app=initializeApp({projectId},projectId),db=getFirestore(app),bucket=getStorage(app).bucket(`${projectId}.firebasestorage.app`);
  const [host,port]=process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');
  const [firestoreHost,firestorePort]=process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const env=await initializeTestEnvironment({projectId,storage:{host,port:Number(port),rules:readFileSync('../storage.rules','utf8')},
    firestore:{host:firestoreHost,port:Number(firestorePort),rules:readFileSync('../firestore.rules','utf8')}});
  const catalog=operationsCatalog(),catalogVersion='photo-storage-v1',date='2026-11-16';
  let now=Date.parse(`${date}T03:00:00Z`);
  const clock=()=>now,options={clock};
  const image=await sharp({create:{width:32,height:32,channels:3,background:'white'}}).jpeg().toBuffer();
  const routeId=catalog.baseRoutes.find(r=>r.staffId==='s1'&&r.period==='morning').id;
  const input=(patch={})=>({date,period:'morning',routeId,kind:'start',requestId:randomUUID(),photoBase64:image.toString('base64'),expectedVersion:1,expectedAvailabilityVersion:0,...patch});
  const read=(staffId='s1',extra={})=>getWorkPhotos(db,bucket,'staff',{staffId,date,period:'morning',...extra},options);
  const rejects=(promise,code)=>assert.rejects(promise,e=>e.code===code);
  try{
    await registerCatalog(db,catalogVersion,catalog);
    for(const [uid,p]of Object.entries({admin:{active:true,role:'admin'},staff:{active:true,role:'staff',staffId:'s1'},other:{active:true,role:'staff',staffId:'s2'},inactive:{active:false,role:'staff',staffId:'s1'}}))await db.doc(`users/${uid}`).create(p);
    await confirm(db,'admin',operationRequest(catalog,date,'morning',catalogVersion,randomUUID()));
    const protectedPaths=['settings/schedules',`schedules/${date}_morning`,`staffSchedules/s1/days/${date}_morning`];
    const before=await Promise.all(protectedPaths.map(async path=>[path,(await db.doc(path).get()).data()]));
    const legacyPath=`attendance/s1/records/${date}_morning_${routeId}_start`;
    await db.doc(legacyPath).create({staffId:'s1',uid:'staff',date,period:'morning',routeId,kind:'start',photo:image,contentType:'image/jpeg'});
    const legacyBefore=(await db.doc(legacyPath).get()).data();
    await t.test('disabled by default; reject roles, wrong course, missing confirmation and dates',async()=>{
      await rejects(registerWorkPhoto(db,bucket,'staff',input(),options),'failed-precondition');
      await db.doc('_workPhotoControl/config').set({enabled:true,allowedCatalogVersions:[catalogVersion],requireAppCheck:false});
      for(const [uid,code]of [['admin','permission-denied'],['other','failed-precondition'],['inactive','permission-denied']])await rejects(registerWorkPhoto(db,bucket,uid,input(),options),code);
      await rejects(registerWorkPhoto(db,bucket,null,input(),options),'unauthenticated');
      await rejects(registerWorkPhoto(db,bucket,'staff',input({staffId:'s2'}),options),'invalid-argument');
      await rejects(registerWorkPhoto(db,bucket,'staff',input({date:'2026-11-15'}),options),'failed-precondition');
      await rejects(registerWorkPhoto(db,bucket,'staff',input({period:'afternoon',kind:'end'}),options),'failed-precondition');
      await rejects(registerWorkPhoto(db,bucket,'staff',input({expectedVersion:2}),options),'failed-precondition');
      await db.doc('_workPhotoControl/config').update({requireAppCheck:true});
      await rejects(registerWorkPhoto(db,bucket,'staff',input(),options),'unauthenticated');
      await db.doc('_workPhotoControl/config').update({requireAppCheck:false});
    });
    await t.test('server rejects fake JPEG, PNG, excessive bytes/pixels and end-before-start',async()=>{
      for(const bytes of [Buffer.from('not JPEG'),Buffer.alloc(MAX_BYTES+1),await sharp(image).png().toBuffer(),await sharp({create:{width:2500,height:2000,channels:3,background:'white'}}).jpeg().toBuffer()])await rejects(jpeg(bytes.toString('base64')),'invalid-argument');
      await rejects(registerWorkPhoto(db,bucket,'staff',input({kind:'end'}),options),'invalid-argument');
      const withExif=await sharp(image).withExif({IFD0:{Artist:'Fictional fixture'}}).jpeg().toBuffer();
      assert.ok((await sharp(withExif).metadata()).exif);
      assert.equal((await sharp(await jpeg(withExif.toString('base64'))).metadata()).exif,undefined);
    });
    await t.test('absence and wrong staff mapping block registration',async()=>{
      await setStaffAbsence(db,'admin',{date,staffId:'s1',periods:['morning'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion});
      await rejects(registerWorkPhoto(db,bucket,'staff',input(),options),'failed-precondition');
      await db.doc(`staffAvailability/${date}/staff/s1`).delete();
      await db.doc('users/staff').update({staffId:'missing'});
      await rejects(registerWorkPhoto(db,bucket,'staff',input(),options),'failed-precondition');
      await db.doc('users/staff').update({staffId:'s1'});
    });
    await t.test('upload failure before object creation never creates a completed attendance record',async()=>{
      const previous=now,day='2026-11-13';now=Date.parse(`${day}T03:00:00Z`);
      try{
        await confirm(db,'admin',operationRequest(catalog,day,'morning',catalogVersion,randomUUID()));
        const disconnected={name:bucket.name,file:()=>({save:async()=>{throw Error('simulated disconnected Storage');}})};
        await rejects(registerWorkPhoto(db,disconnected,'staff',input({date:day}),options),'unavailable');
        assert.equal((await getWorkPhotos(db,bucket,'staff',{staffId:'s1',date:day,period:'morning'},options)).records.length,0);
      }finally{now=previous;}
    });
    let start,original;
    await t.test('upload then network failure leaves no completed record; same ID resumes after lease expiry',async()=>{
      original=input();
      await rejects(registerWorkPhoto(db,bucket,'staff',original,{clock,afterUpload:async()=>{throw Error('simulated network loss');}}),'unavailable');
      assert.equal((await read()).records.length,0);
      await rejects(registerWorkPhoto(db,bucket,'staff',original,options),'aborted');
      now+=120001;
      start=await registerWorkPhoto(db,bucket,'staff',original,options);
      assert.equal(start.staffId,'s1');assert.equal(start.kind,'start');
      const saved=(await db.doc(`workPhotoRecords/s1/records/${start.recordId}`).get()).data();
      assert.equal(saved.schemaVersion,2);assert.equal(saved.photo.contentType,'image/jpeg');
      assert.ok(saved.registeredAt.toMillis()>Date.now()-60000);
      assert.equal(saved.expiresAt.toMillis(),now+30*86400000);
      assert.equal(typeof saved.photo.generation,'string');
      assert.ok(!(await bucket.file(saved.photo.path).getMetadata())[0].metadata.firebaseStorageDownloadTokens);
      assert.deepEqual(await registerWorkPhoto(db,bucket,'staff',original,options),start);
      assert.deepEqual(await registerWorkPhoto(db,bucket,'staff',Object.fromEntries(Object.entries(original).reverse()),options),start);
      await rejects(registerWorkPhoto(db,bucket,'staff',{...original,photoBase64:(await sharp(image).modulate({brightness:0.5}).jpeg().toBuffer()).toString('base64')},options),'already-exists');
      await rejects(registerWorkPhoto(db,bucket,'staff',input(),options),'already-exists');
    });
    await t.test('owner/admin read private bytes; other staff/anonymous and all direct Storage clients denied',async()=>{
      const photo=await read('s1',{recordId:start.recordId});assert.ok(Buffer.from(photo.photoBase64,'base64').length>0);
      assert.equal((await getWorkPhotos(db,bucket,'admin',{staffId:'s1',date,period:'morning'},options)).records.length,1);
      for(const uid of ['other','inactive'])await rejects(getWorkPhotos(db,bucket,uid,{staffId:'s1',date,period:'morning'},options),'permission-denied');
      await rejects(getWorkPhotos(db,bucket,null,{staffId:'s1',date,period:'morning'},options),'unauthenticated');
      const saved=(await db.doc(`workPhotoRecords/s1/records/${start.recordId}`).get()).data();
      for(const context of [env.authenticatedContext('staff'),env.authenticatedContext('admin'),env.unauthenticatedContext()]){
        const object=ref(context.storage(bucket.name),saved.photo.path);
        await assertFails(uploadBytes(object,image,{contentType:'image/jpeg'}));
        await assertFails(getBytes(object));
        await assertFails(deleteObject(object));
        await assertFails(updateMetadata(object,{contentType:'text/plain'}));
        await assertFails(listAll(ref(context.storage(bucket.name),'workPhotos/v1/')));
        const directRecord=doc(context.firestore(),`workPhotoRecords/s1/records/${start.recordId}`);
        await assertFails(getDoc(directRecord));
        await assertFails(setDoc(directRecord,{bypass:true}));
      }
    });
    await t.test('afternoon end is independent of morning records; concurrent requests cannot overwrite',async()=>{
      await confirm(db,'admin',operationRequest(catalog,date,'afternoon',catalogVersion,randomUUID()));
      const afternoonRoute=catalog.baseRoutes.find(r=>r.staffId==='s1'&&r.period==='afternoon').id;
      const end=input({period:'afternoon',routeId:afternoonRoute,kind:'end'});
      const results=await Promise.allSettled([registerWorkPhoto(db,bucket,'staff',end,options),registerWorkPhoto(db,bucket,'staff',{...end,requestId:randomUUID()},options)]);
      assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
      const records=(await getWorkPhotos(db,bucket,'staff',{staffId:'s1',date,period:'afternoon'},options)).records;assert.equal(records.length,1);assert.equal(records[0].kind,'end');
      assert.deepEqual((await read('s1',{recordId:start.recordId})).registeredAt,start.registeredAt);
    });
    await t.test('missing morning start does not block afternoon end; wrong period kind is rejected',async()=>{
      const previous=now,day='2026-11-20';now=Date.parse(`${day}T08:00:00Z`);
      try {
        await confirm(db,'admin',operationRequest(catalog,day,'afternoon',catalogVersion,randomUUID()));
        const afternoonRoute=catalog.baseRoutes.find(r=>r.staffId==='s1'&&r.period==='afternoon').id;
        const request=input({date:day,period:'afternoon',routeId:afternoonRoute,kind:'end'});
        await rejects(registerWorkPhoto(db,bucket,'staff',{...request,kind:'start'},options),'invalid-argument');
        assert.equal((await registerWorkPhoto(db,bucket,'staff',request,options)).kind,'end');
        assert.equal((await getWorkPhotos(db,bucket,'staff',{staffId:'s1',date:day,period:'morning'},options)).records.length,0);
      } finally {now=previous;}
    });
    await t.test('in-flight reassignment or revocation cannot complete an uploaded photo',async()=>{
      const next='2026-11-17';now=Date.parse(`${next}T03:00:00Z`);
      const schedule=operationRequest(catalog,next,'morning',catalogVersion,randomUUID());await confirm(db,'admin',schedule);
      const request=input({date:next});
      await rejects(registerWorkPhoto(db,bucket,'staff',request,{clock,afterUpload:async()=>{
        await setStaffAbsence(db,'admin',{date:next,staffId:'s1',periods:['morning'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion});
      }}),'failed-precondition');
      assert.equal((await getWorkPhotos(db,bucket,'staff',{staffId:'s1',date:next,period:'morning'},options)).records.length,0);
      for(const [day,revoke]of [
        ['2026-11-18',async()=>{await db.doc('users/staff').update({active:false});}],
        ['2026-11-19',async schedule=>{await confirm(db,'admin',{...schedule,expectedVersion:1,requestId:randomUUID(),routes:schedule.routes.map(r=>r.staffId==='s1'?{...r,staffId:'s3'}:r)});}],
      ]){
        now=Date.parse(`${day}T03:00:00Z`);
        const schedule=operationRequest(catalog,day,'morning',catalogVersion,randomUUID());
        await confirm(db,'admin',schedule);
        await assert.rejects(registerWorkPhoto(db,bucket,'staff',input({date:day}),{clock,afterUpload:()=>revoke(schedule)}),e=>['permission-denied','failed-precondition'].includes(e.code));
        await db.doc('users/staff').update({active:true});
        assert.equal((await getWorkPhotos(db,bucket,'staff',{staffId:'s1',date:day,period:'morning'},options)).records.length,0);
      }
    });
    await t.test('cleanup is dry-run by default; orphan recovery and 30-day expiry delete only owned generations',async()=>{
      now+=86400001;
      const dry=await cleanupWorkPhotos(db,bucket,{clock});assert.equal(dry.pending,4);assert.equal(dry.deleted,0);
      const apply=await cleanupWorkPhotos(db,bucket,{clock,apply:true});assert.equal(apply.deleted,4);
      assert.equal((await cleanupWorkPhotos(db,bucket,{clock,apply:true})).deleted,0);
      now+=31*86400000;
      assert.equal((await read()).records.length,0);
      await rejects(read('s1',{recordId:start.recordId}),'not-found');
      assert.equal((await cleanupWorkPhotos(db,bucket,{clock,apply:true})).expired,3);
      assert.equal((await bucket.getFiles({prefix:'workPhotos/v1/'}))[0].length,0);
    });
    for(const [path,data]of before)assert.deepEqual((await db.doc(path).get()).data(),data);
    assert.deepEqual((await db.doc(legacyPath).get()).data(),legacyBefore);
  }finally{await env.cleanup();await deleteApp(app);}
});
test('new Callable HTTP entry points use Auth, Firestore and private Storage Emulators together',async()=>{
  const authHost=process.env.FIREBASE_AUTH_EMULATOR_HOST,functionsHost=process.env.FUNCTIONS_EMULATOR_HOST;
  if(![authHost,functionsHost].every(v=>/^127\.0\.0\.1:\d+$/.test(v||'')))throw Error('Loopback required');
  const projectId='demo-senior-transport',app=initializeApp({projectId},'work-photo-http'),db=getFirestore(app);
  const clockDate=new Date(Date.now()+9*3600000).toISOString().slice(0,10);
  try{
    const signup=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`,{
      method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:`photo-${randomUUID()}@example.test`,password:randomUUID(),returnSecureToken:true}),signal:AbortSignal.timeout(10000),
    });
    assert.equal(signup.status,200);const auth=await signup.json();
    await db.doc('users/work-photo-http-admin').set({active:true,role:'admin'});
    // Reuse a schedule already confirmed by the earlier suite without overwriting it.
    const scheduleRef=db.doc(`schedules/${clockDate}_afternoon`);
    let schedule=(await scheduleRef.get()).data();
    if(!schedule){
      const catalog=operationsCatalog(),version='work-photo-callable-v1';await registerCatalog(db,version,catalog);
      await confirm(db,'work-photo-http-admin',operationRequest(catalog,clockDate,'afternoon',version,randomUUID()));
      schedule=(await scheduleRef.get()).data();
    }
    let route,availabilityVersion;
    for(const candidate of schedule.routes){
      const absence=(await db.doc(`staffAvailability/${clockDate}/staff/${candidate.staffId}`).get()).data();
      if(!(absence?.unavailablePeriods||[]).includes('afternoon')){route=candidate;availabilityVersion=absence?.version??0;break;}
    }
    assert.ok(route,'A confirmed available staff assignment is required');
    await db.doc(`users/${auth.localId}`).create({active:true,role:'staff',staffId:route.staffId});
    await db.doc('_workPhotoControl/config').set({enabled:true,allowedCatalogVersions:[schedule.catalogVersion],requireAppCheck:false});
    const invoke=async(name,data,token=auth.idToken)=>{
      const response=await fetch(`http://${functionsHost}/${projectId}/asia-northeast3/${name}`,{
        method:'POST',headers:{'content-type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify({data}),signal:AbortSignal.timeout(30000),
      });return {status:response.status,body:await response.json()};
    };
    const photo=await sharp({create:{width:16,height:16,channels:3,background:'white'}}).jpeg().toBuffer();
    const request={date:clockDate,period:'afternoon',routeId:route.baseRouteId,
      kind:'end',requestId:randomUUID(),photoBase64:photo.toString('base64'),expectedVersion:schedule.version,expectedAvailabilityVersion:availabilityVersion};
    assert.equal((await invoke('registerWorkPhoto',request,null)).status,401);
    const saved=await invoke('registerWorkPhoto',request);assert.equal(saved.status,200);
    const result=await invoke('getWorkPhotos',{staffId:route.staffId,date:clockDate,period:'afternoon',recordId:saved.body.result.recordId});
    assert.equal(result.status,200);assert.ok(result.body.result.photoBase64);assert.equal(result.body.result.staffId,route.staffId);
    assert.equal(JSON.stringify(result.body).includes('https://'),false);
  }finally{await deleteApp(app);}
});
