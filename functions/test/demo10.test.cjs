'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {getStorage}=require('firebase-admin/storage');
const sharp=require('sharp');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc}=require('firebase/firestore');
const {VERSION,PREVIOUS,buildManifest,makePlan,requestFor,baseline}=require('../../tools/demo10_fixture.cjs');
const registration=require('../../tools/demo10_registration.cjs');
// Per-case demo namespaces share the same loopback Emulator. Do not inherit
// the runner's different demo project ID as the operator's target project.
const testEnv={FIRESTORE_EMULATOR_HOST:process.env.FIRESTORE_EMULATOR_HOST};
const register=(db,m,o={})=>registration.register(db,m,{...o,env:testEnv});
const transition=(db,m,o={})=>registration.transition(db,m,{...o,env:testEnv});
const {parse}=require('../../tools/register-demo10-catalog.cjs');
const {confirm}=require('../schedule-service');
const {setStaffAbsence}=require('../staff-absence-service');
const {productionSuggest}=require('../production-ai-service');
const {registerWorkPhoto,getWorkPhotos}=require('../work-photo-service');
const {geometryForCatalog,totalDistance}=require('../schedule-distance');
if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||''))throw Error('Demo loopback required');
const manifest=buildManifest(),plan=makePlan(manifest),date='2026-12-07';
const options=(db,extra={})=>({apply:true,confirmation:db.projectId,approval:VERSION,...extra});
async function withDemo(name,body){const app=initializeApp({projectId:`demo-demo10-${name}-${randomUUID().slice(0,5)}`},name),db=getFirestore(app);
  try{await body(db,app);}finally{await deleteApp(app);}}
async function seedOld(db){
  const old=baseline();for(const [name,items]of Object.entries(old.collections))for(const {id,...data}of items)await db.doc(`catalogs/${PREVIOUS}/${name}/${id}`).create(data);
  await db.doc(`catalogs/${PREVIOUS}`).create(old.catalogMetadata);
  await db.doc('settings/schedules').create({catalogVersion:PREVIOUS,operatorNote:'keep'});
  for(const [uid,profile]of Object.entries({admin:{active:true,role:'admin'},staff:{active:true,role:'staff',staffId:'s1'},other:{active:true,role:'staff',staffId:'s2'}}))await db.doc(`users/${uid}`).create(profile);
}
const request=(period='morning',day=date)=>({...requestFor(manifest.collections,day,period),requestId:randomUUID()});
test('demo10 manifest preserves baseline identity, routes, weekday, natural names and complete synthetic geometry',()=>{
  assert.deepEqual(JSON.parse(readFileSync('../docs/fixtures/demo-10x24-v1.baseline.json','utf8')),manifest);
  assert.equal(plan.documents.length,58);assert.deepEqual(plan.counts,{staff:10,vehicles:8,passengers:24,baseRoutes:16});
  const old=baseline().collections,c=manifest.collections;
  assert.deepEqual(c.staff.slice(0,3),old.staff);
  for(let i=0;i<5;i++){assert.equal(c.passengers[i].id,old.passengers[i].id);assert.equal(c.passengers[i].address,old.passengers[i].address);assert.equal(c.passengers[i].note,old.passengers[i].note);assert.ok(!c.passengers[i].name.includes('가상'));}
  for(const route of old.baseRoutes){const r=c.baseRoutes.find(r=>r.id===route.id);assert.deepEqual(r.passengerIds.slice(0,route.passengerIds.length),route.passengerIds);}
  assert.ok(c.vehicles.every(v=>v.passengerCapacity===4));
  assert.ok(Number.isFinite(totalDistance(request().routes,geometryForCatalog(c,VERSION))));
  const bad=structuredClone(manifest);bad.collections.vehicles[0].passengerCapacity=5;assert.throws(()=>makePlan(bad));
});
test('demo10 CLI rejects unsafe targets, ambiguity and approvals without Firebase initialization',()=>{
  assert.equal(parse(['register','--project','senior-transport-app'],{}).apply,false);
  assert.equal(parse(['rollback','--project','senior-transport-app','--apply','--confirm-project','senior-transport-app','--approve-catalog',PREVIOUS],{}).rollback,true);
  for(const args of [[],['register'],['register','--project','other'],['register','--project','senior-transport-app','--apply'],
    ['switch','--project','senior-transport-app','--verify'],['register','--project','senior-transport-app','--force'],
    ['register','--project','senior-transport-app','--apply','--dry-run']])assert.throws(()=>parse(args,{}));
  assert.throws(()=>parse(['register','--project','senior-transport-app'],{FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080'}));
});
test('atomic registration, create-only conflicts, tamper verification and preserved operational sentinels',()=>withDemo('registration',async db=>{
  await seedOld(db);
  const sentinels={'_aiControl/config':{mode:'off'},'_workPhotoControl/config':{enabled:false},'attendance/s1/records/keep':{keep:true},'catalogs/ai-test-25x80-v1':{keep:true}};
  for(const [p,d]of Object.entries(sentinels))await db.doc(p).create(d);
  assert.equal((await register(db,manifest)).status,'DRY_RUN_OK');assert.equal((await db.doc(plan.parentPath).get()).exists,false);
  const results=await Promise.all([register(db,manifest,options(db)),register(db,manifest,options(db))]);
  assert.deepEqual(results.map(r=>r.status).sort(),['APPLIED','BLOCKED_EXISTING_CATALOG']);
  assert.equal((await register(db,manifest,{verify:true})).verified,true);
  assert.equal((await db.doc('settings/schedules').get()).data().catalogVersion,PREVIOUS);
  for(const [p,d]of Object.entries(sentinels))assert.deepEqual((await db.doc(p).get()).data(),d);
  await db.doc(`${plan.parentPath}/staff/s10`).update({name:'changed'});
  assert.equal((await register(db,manifest,{verify:true})).status,'VERIFICATION_FAILED');
  await assert.rejects(transition(db,manifest,options(db)),/TARGET_CATALOG_INVALID/);
}));
test('orphan descendant and partial catalog are never filled or deleted',async()=>{
  for(const [i,path]of [plan.parentPath,`${plan.parentPath}/staff/s1/extra/keep`].entries())await withDemo(`partial${i}`,async db=>{
    await db.doc(path).create({keep:true});assert.equal((await register(db,manifest,options(db))).status,'BLOCKED_EXISTING_CATALOG');
    assert.deepEqual((await db.doc(path).get()).data(),{keep:true});
  });
});
test('injected failure during catalog writes leaves no ready parent or partial children',()=>withDemo('atomicfailure',async db=>{
  let creates=0;
  const injected=new Proxy(db,{get(target,key){
    if(key==='runTransaction')return action=>target.runTransaction(tx=>action(new Proxy(tx,{get(t,k){
      if(k==='create')return(ref,data)=>{if(++creates===20)throw Error('INJECTED_FAILURE');return t.create(ref,data);};
      const value=Reflect.get(t,k,t);return typeof value==='function'?value.bind(t):value;
    }})));
    const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
  }});
  await assert.rejects(register(injected,manifest,options(db)),/INJECTED_FAILURE/);
  assert.equal((await db.doc(plan.parentPath).get()).exists,false);
  assert.equal((await db.collection(`${plan.parentPath}/staff`).get()).empty,true);
}));
test('switch, AM/PM confirmations, absence handoff, passenger absence/move, capacity, duplicates and rollback',()=>withDemo('flows',async db=>{
  await seedOld(db);
  const oldInput=requestFor(baseline().collections,'2026-12-06','morning',PREVIOUS);
  await confirm(db,'admin',oldInput);
  const oldRef=db.doc('schedules/2026-12-06_morning'),before=await oldRef.get();
  await db.doc('attendance/s1/records/old').create({keep:true});
  await setStaffAbsence(db,'admin',{date:'2026-12-08',staffId:'s2',periods:['afternoon'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion:PREVIOUS});
  await register(db,manifest,options(db));
  const dry=await transition(db,manifest);assert.equal(dry.preservedPhotoRecords,1);assert.equal(dry.status,'DRY_RUN_OK');
  await transition(db,manifest,options(db));
  const retainedAbsence=request('afternoon','2026-12-08');retainedAbsence.expectedAvailabilityVersions.s2=1;
  await assert.rejects(confirm(db,'admin',retainedAbsence),{code:'failed-precondition'});
  assert.equal((await db.doc('settings/schedules').get()).data().operatorNote,'keep');
  await assert.rejects(confirm(db,'admin',{...oldInput,catalogVersion:VERSION,expectedVersion:1,requestId:randomUUID()}),{code:'failed-precondition'});
  await assert.rejects(confirm(db,'staff',request()),{code:'permission-denied'});
  for(const period of ['morning','afternoon'])await confirm(db,'admin',request(period));
  for(let i=1;i<=8;i++)assert.equal((await db.doc(`staffSchedules/s${i}/days/${date}_morning`).get()).data().catalogVersion,VERSION);
  const absence={date,staffId:'s1',periods:['morning'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion:VERSION};
  await setStaffAbsence(db,'admin',absence);
  const updated={...request(),expectedVersion:1};
  await assert.rejects(confirm(db,'admin',updated),{code:'failed-precondition'});
  updated.routes[0].staffId='s9';
  updated.absentIds=['p4'];updated.routes[1].passengerIds=['p5','p6'];
  updated.routes[0].passengerIds=updated.routes[0].passengerIds.filter(id=>id!=='p3');updated.routes[1].passengerIds.push('p3');
  updated.expectedAvailabilityVersions.s1=1;
  await confirm(db,'admin',updated);
  assert.equal((await db.doc(`staffSchedules/s1/days/${date}_morning`).get()).exists,false);
  assert.equal((await db.doc(`staffSchedules/s9/days/${date}_morning`).get()).data().routes.length,1);
  assert.equal((await db.doc(`staffSchedules/s1/days/${date}_afternoon`).get()).exists,true);
  const bad={...request('afternoon'),expectedVersion:1};bad.routes[1].staffId='s1';
  await assert.rejects(confirm(db,'admin',bad),{code:'invalid-argument'});
  const overload={...request('afternoon'),expectedVersion:1};overload.routes[0].passengerIds.push(...overload.routes[1].passengerIds.slice(0,2));overload.routes[1].passengerIds=overload.routes[1].passengerIds.slice(2);
  await assert.rejects(confirm(db,'admin',overload),{code:'invalid-argument'});
  await assert.rejects(confirm(db,'admin',request('morning','2026-12-11')),{code:'invalid-argument'}); // s3 Friday off retained.
  assert.ok((await oldRef.get()).updateTime.isEqual(before.updateTime));
  await transition(db,manifest,options(db,{rollback:true,approval:PREVIOUS}));
  assert.equal((await db.doc('settings/schedules').get()).data().catalogVersion,PREVIOUS);
  assert.equal((await db.doc(`schedules/${date}_morning`).get()).data().catalogVersion,VERSION);
  assert.deepEqual((await db.doc('attendance/s1/records/old').get()).data(),{keep:true});
  assert.deepEqual((await db.doc(`staffAvailability/${date}/staff/s1`).get()).data().unavailablePeriods,['morning']);
}));
test('rollback reports active new accounts, concurrent pointer switches and confirmation preserve catalog pinning',()=>withDemo('races',async db=>{
  await seedOld(db);await register(db,manifest,options(db));
  const results=await Promise.allSettled([transition(db,manifest,options(db)),transition(db,manifest,options(db)),confirm(db,'admin',requestFor(baseline().collections,date,'morning',PREVIOUS))]);
  assert.equal(results.slice(0,2).filter(r=>r.status==='fulfilled'&&r.value.status==='SWITCHED').length,1);
  const confirmed=(await db.doc(`schedules/${date}_morning`).get()).data();if(confirmed)assert.equal(confirmed.catalogVersion,PREVIOUS);
  await db.doc('users/new-test').create({active:true,role:'staff',staffId:'s9'});
  assert.equal((await transition(db,manifest,{rollback:true})).status,'BLOCKED_STAFF_MAPPING');
  assert.equal((await transition(db,manifest,options(db,{rollback:true,approval:PREVIOUS}))).status,'BLOCKED_STAFF_MAPPING');
  assert.equal((await db.doc('settings/schedules').get()).data().catalogVersion,VERSION);
}));
test('ordinary production AI path accepts demo10, anonymizes coordinates, preserves schedule and respects allowlist',()=>withDemo('ai',async db=>{
  await seedOld(db);await register(db,manifest,options(db));await transition(db,manifest,options(db));
  const control=db.doc('_aiControl/config');await control.create({mode:'test',allowedAdminUids:['admin'],allowedCatalogVersions:[VERSION],allowFictionalLocations:true,projectDailyLimit:1,adminDailyLimit:1,cooldownSeconds:1,requireAppCheck:false});
  let calls=0;const generate=async data=>{calls++;assert.ok(data.locationModel);const wire=JSON.stringify(data);
    for(const p of manifest.collections.passengers){assert.ok(!wire.includes(p.name));assert.ok(!wire.includes(p.address));assert.ok(!wire.includes(JSON.stringify(p.id)));}
    return {routes:data.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:r.passengerIds})),reasons:['기존 배정 유지']};};
  const result=await productionSuggest(db,'admin',request(),{generate});assert.equal(calls,1);assert.equal(result.routes.length,8);
  assert.equal((await db.collection('schedules').get()).empty,true);
  // A second simulated day has a genuine absence. Only a free available alias
  // may replace its owner; the normal server path validates the spare staff.
  await setStaffAbsence(db,'admin',{date,staffId:'s1',periods:['morning'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion:VERSION});
  const absent=request();absent.expectedAvailabilityVersions.s1=1;
  const repaired=await productionSuggest(db,'admin',absent,{clock:()=>Date.now()+86400000,generate:async data=>{
    calls++;const used=new Set(data.routes.map(r=>r.staffId));const spare=data.availableStaffIds.find(id=>!used.has(id));
    return {routes:data.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:data.availableStaffIds.includes(r.staffId)?r.staffId:spare,passengerIds:r.passengerIds})),reasons:['예비 직원 인계']};
  }});
  assert.ok(['s9','s10'].includes(repaired.routes[0].staffId));
  assert.equal((await db.collection('schedules').get()).empty,true);
  await assert.rejects(productionSuggest(db,'staff',request(),{generate}),{code:'permission-denied'});
  await control.update({allowedCatalogVersions:[PREVIOUS]});await assert.rejects(productionSuggest(db,'admin',request(),{generate}),{code:'permission-denied'});assert.equal(calls,2);
}));
test('today photo start/end with existing staff UID; old records kept and owner/admin-only access',()=>withDemo('photos',async(db,app)=>{
  await seedOld(db);await register(db,manifest,options(db));await transition(db,manifest,options(db));
  const today=new Date(Date.now()+9*3600000).toISOString().slice(0,10),input=request('morning',today);
  // Friday retains s3 off: explicitly hand that route to a reserve before confirming.
  if(new Date(`${today}T00:00:00Z`).getUTCDay()===5)input.routes.find(r=>r.staffId==='s3').staffId='s9';
  await confirm(db,'admin',input);
  await db.doc('_workPhotoControl/config').create({enabled:true,allowedCatalogVersions:[VERSION,PREVIOUS],requireAppCheck:false});
  await db.doc('attendance/s1/records/old').create({keep:true});
  const bucket=getStorage(app).bucket(`${db.projectId}.firebasestorage.app`),photoBase64=(await sharp({create:{width:16,height:16,channels:3,background:'white'}}).jpeg().toBuffer()).toString('base64');
  const photo={date:today,period:'morning',routeId:'morning-a',kind:'start',requestId:randomUUID(),photoBase64,expectedVersion:1,expectedAvailabilityVersion:0};
  await assert.rejects(registerWorkPhoto(db,bucket,'other',photo),{code:'failed-precondition'});
  const start=await registerWorkPhoto(db,bucket,'staff',photo);await registerWorkPhoto(db,bucket,'staff',{...photo,kind:'end',requestId:randomUUID()});
  const query={staffId:'s1',date:today,period:'morning'};
  assert.equal((await getWorkPhotos(db,bucket,'admin',query)).records.length,2);
  assert.ok((await getWorkPhotos(db,bucket,'staff',{...query,recordId:start.recordId})).photoBase64);
  await assert.rejects(getWorkPhotos(db,bucket,'other',query),{code:'permission-denied'});
  const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const rules=await initializeTestEnvironment({projectId:db.projectId,firestore:{host,port:Number(port),rules:readFileSync('../firestore.rules','utf8')}});
  try{
    await assertSucceeds(getDoc(doc(rules.authenticatedContext('staff').firestore(),`staffSchedules/s1/days/${today}_morning`)));
    await assertFails(getDoc(doc(rules.authenticatedContext('other').firestore(),`staffSchedules/s1/days/${today}_morning`)));
    await assertFails(getDoc(doc(rules.authenticatedContext('other').firestore(),`workPhotoRecords/s1/records/${start.recordId}`)));
  }finally{await rules.cleanup();}
  await transition(db,manifest,options(db,{rollback:true,approval:PREVIOUS}));
  assert.equal((await getWorkPhotos(db,bucket,'staff',query)).records.length,2);
  assert.ok((await getWorkPhotos(db,bucket,'admin',{...query,recordId:start.recordId})).photoBase64);
  assert.deepEqual((await db.doc('attendance/s1/records/old').get()).data(),{keep:true});
}));
