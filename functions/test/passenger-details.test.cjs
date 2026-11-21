'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {readFileSync}=require('node:fs');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc}=require('firebase/firestore');
const {getPassengerDetails,updatePassengerDetails}=require('../passenger-details');
const {confirm}=require('../schedule-service');
const {registerCatalog}=require('../../tools/fictional_catalog.cjs');
const {operationsCatalog,operationRequest}=require('../../tools/operations_fixture.cjs');
if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||''))throw Error('Loopback Emulator required');
test('persistent morning defaults and notes: optimistic updates, projections and private staff access',async t=>{
  const projectId='demo-passenger-details',app=initializeApp({projectId},projectId),db=getFirestore(app);
  const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const env=await initializeTestEnvironment({projectId,firestore:{host,port:Number(port),rules:readFileSync('../firestore.rules','utf8')}});
  const catalog=operationsCatalog(),version='details-v1',date='2026-11-16';
  const load={catalogVersion:version,date,period:'morning'};
  const input=(patch={})=>({catalogVersion:version,passengerId:'p1',expectedVersion:0,note:'천천히 안내',defaultMorningMinute:510,...patch});
  const rejects=(promise,code)=>assert.rejects(promise,e=>e.code===code);
  try {
    await registerCatalog(db,version,catalog);
    for(const [uid,p]of Object.entries({admin:{active:true,role:'admin'},staff:{active:true,role:'staff',staffId:'s1'},other:{active:true,role:'staff',staffId:'s2'},inactive:{active:false,role:'admin'}}))await db.doc(`users/${uid}`).create(p);
    await confirm(db,'admin',operationRequest(catalog,date,'morning',version,randomUUID()));
    const before=(await db.doc(`schedules/${date}_morning`).get()).data();
    const original=(await db.doc(`catalogs/${version}/passengers/p1`).get()).data();
    await t.test('admin saves and reloads default; other roles and client writes denied',async()=>{
      for(const uid of ['staff','other','inactive'])await rejects(updatePassengerDetails(db,uid,input()),'permission-denied');
      await rejects(updatePassengerDetails(db,null,input()),'unauthenticated');
      await updatePassengerDetails(db,'admin',input());
      const actual=(await getPassengerDetails(db,'admin',load)).passengers.find(p=>p.id==='p1');
      assert.equal(actual.defaultMorningMinute,510);assert.equal(actual.note,'천천히 안내');
      for(const uid of ['admin','staff']) {
        const client=env.authenticatedContext(uid).firestore(),ref=doc(client,`catalogs/${version}/passengerSettings/p1`);
        await assertFails(getDoc(ref));await assertFails(setDoc(ref,{note:'bypass'}));
      }
    });
    await t.test('staff only receives assigned passenger details; arbitrary scope and inactive users denied',async()=>{
      assert.equal((await getPassengerDetails(db,'staff',load)).passengers.some(p=>p.id==='p1'),true);
      assert.equal((await getPassengerDetails(db,'other',load)).passengers.some(p=>p.id==='p1'),false);
      await rejects(getPassengerDetails(db,'inactive',load),'permission-denied');
      await rejects(getPassengerDetails(db,'staff',{...load,passengerId:'p1'}),'invalid-argument');
      await rejects(getPassengerDetails(db,'staff',{...load,date:'2026-11-17'}),'permission-denied');
    });
    await t.test('concurrent updates conflict; notes can be removed; times and original catalog remain unchanged',async()=>{
      const result=await Promise.allSettled([updatePassengerDetails(db,'admin',input({expectedVersion:1,note:'새 안내',defaultMorningMinute:525})),updatePassengerDetails(db,'admin',input({expectedVersion:1,note:'다른 안내',defaultMorningMinute:540}))]);
      assert.equal(result.filter(r=>r.status==='fulfilled').length,1);assert.equal(result.find(r=>r.status==='rejected').reason.code,'aborted');
      await updatePassengerDetails(db,'admin',input({expectedVersion:2,note:'',defaultMorningMinute:null}));
      const next=(await getPassengerDetails(db,'staff',load)).passengers.find(p=>p.id==='p1');
      assert.equal(next.note,'');assert.equal(next.defaultMorningMinute,null);
      assert.deepEqual((await db.doc(`schedules/${date}_morning`).get()).data(),before);
      assert.deepEqual((await db.doc(`catalogs/${version}/passengers/p1`).get()).data(),original);
    });
    await t.test('future confirmations freeze chosen manual times and project the latest notes',async()=>{
      await updatePassengerDetails(db,'admin',input({expectedVersion:3,note:'문 앞에서 안내',defaultMorningMinute:555}));
      const request=operationRequest(catalog,'2026-11-17','morning',version,randomUUID());
      const r=request.routes.find(r=>r.passengerIds.includes('p1'));r.estimatedVisitMinutes.p1=555;r.estimatedVisitSources={p1:'manual'};
      await confirm(db,'admin',request);
      const projection=(await db.doc('staffSchedules/s1/days/2026-11-17_morning').get()).data();
      assert.equal(projection.catalog.passengers.find(p=>p.id==='p1').note,'문 앞에서 안내');
      const frozen=(await db.doc('schedules/2026-11-17_morning').get()).data();
      await updatePassengerDetails(db,'admin',input({expectedVersion:4,defaultMorningMinute:600}));
      assert.deepEqual((await db.doc('schedules/2026-11-17_morning').get()).data(),frozen);
      for(const patch of [{defaultMorningMinute:-1},{defaultMorningMinute:1440},{defaultMorningMinute:2.5},{note:'x'.repeat(2001)}])await rejects(updatePassengerDetails(db,'admin',input(patch)),'invalid-argument');
    });
    await t.test('reassigning a course removes departed staff access to its passenger details',async()=>{
      const request=operationRequest(catalog,'2026-11-18','morning',version,randomUUID());
      request.routes=request.routes.map(r=>r.staffId==='s1'?{...r,staffId:'s3'}:r);
      await confirm(db,'admin',request);
      await rejects(getPassengerDetails(db,'staff',{...load,date:'2026-11-18'}),'permission-denied');
    });
  } finally {await env.cleanup();await deleteApp(app);}
});

test('passenger detail Callables verify real Emulator Auth and return serialized settings',async()=>{
  const authHost=process.env.FIREBASE_AUTH_EMULATOR_HOST,functionsHost=process.env.FUNCTIONS_EMULATOR_HOST;
  if(![authHost,functionsHost].every(v=>/^127\.0\.0\.1:\d+$/.test(v||'')))throw Error('Loopback Auth/Functions required');
  const app=initializeApp({projectId:'demo-senior-transport'},'passenger-details-http'),db=getFirestore(app);
  try {
    const response=await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`,{
      method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:`details-${randomUUID()}@example.invalid`,password:randomUUID(),returnSecureToken:true}),signal:AbortSignal.timeout(10000)});
    assert.equal(response.status,200);const auth=await response.json();
    await db.doc(`users/${auth.localId}`).create({active:true,role:'admin'});
    const version=`details-http-${randomUUID().slice(0,8)}`;
    await db.doc(`catalogs/${version}`).create({ready:true,fictional:true,schemaVersion:1});
    await db.doc(`catalogs/${version}/passengers/p1`).create({name:'김영숙',address:'시연용 위치',note:'기존 안내'});
    const call=async(name,data,token=auth.idToken)=>{
      const r=await fetch(`http://${functionsHost}/demo-senior-transport/asia-northeast3/${name}`,{
        method:'POST',headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},body:JSON.stringify({data}),signal:AbortSignal.timeout(30000)});
      return {status:r.status,body:await r.json()};
    };
    const scope={catalogVersion:version,date:'2026-11-18',period:'morning'};
    assert.equal((await call('getPassengerDetails',scope,null)).status,401);
    const saved=await call('updatePassengerDetails',{catalogVersion:version,passengerId:'p1',expectedVersion:0,note:'천천히 안내',defaultMorningMinute:515});
    assert.equal(saved.status,200);assert.equal(saved.body.result.defaultMorningMinute,515);
    const loaded=await call('getPassengerDetails',scope);
    assert.equal(loaded.status,200);assert.equal(loaded.body.result.passengers[0].note,'천천히 안내');
    await db.doc(`users/${auth.localId}`).update({active:false});
    assert.equal((await call('getPassengerDetails',scope)).status,403);
  } finally {await deleteApp(app);}
});
