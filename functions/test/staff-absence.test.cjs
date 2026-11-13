'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {readFileSync} = require('node:fs');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, getDocs, collection, setDoc} = require('firebase/firestore');
const {registerCatalog} = require('../../tools/fictional_catalog.cjs');
const {operationsCatalog, operationRequest} = require('../../tools/operations_fixture.cjs');
const {setStaffAbsence} = require('../staff-absence-service');
const {confirm} = require('../schedule-service');

// Separate demo namespace: never touches the other integration suite's fixtures.
if (process.env.GCLOUD_PROJECT !== 'demo-senior-transport' ||
    !/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
  throw new Error('Loopback demo Emulator required');
}
test('A-1 date-specific absence, transactional confirmation and security (20 staff / 80 passengers)', async (t) => {
  const projectId = 'demo-staff-absence';
  const app = initializeApp({projectId}, projectId);
  const db = getFirestore(app);
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const env = await initializeTestEnvironment({projectId, firestore:{host, port:Number(port), rules:readFileSync('../firestore.rules','utf8')}});
  const catalog = operationsCatalog();
  await registerCatalog(db,'absence-v1',catalog);
  for (const [uid, profile] of Object.entries({adminA:{role:'admin',active:true}, adminB:{role:'admin',active:true}, staffA:{role:'staff',staffId:'s1',active:true}, inactive:{role:'admin',active:false}})) {
    await db.doc(`users/${uid}`).set(profile);
  }
  const absence = (date, overrides={}) => ({date,staffId:'s1',periods:['morning'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion:'absence-v1',...overrides});
  const schedule = (date, overrides={}) => ({...operationRequest(catalog,date,'morning','absence-v1',randomUUID()),...overrides});
  const ref = (date,staff='s1') => db.doc(`staffAvailability/${date}/staff/${staff}`);
  const rejects = (promise, code) => assert.rejects(promise,(error)=>error.code===code);
  try {
    await t.test('empty collection succeeds with A-1 rules; the same absent records are denied by pre-A-1 rules', async () => {
      const path = 'staffAvailability/2026-12-31/staff';
      const adminClient = env.authenticatedContext('adminA').firestore();
      const empty = await assertSucceeds(getDocs(collection(adminClient,path)));
      assert.equal(empty.empty,true);
      assert.equal(empty.metadata.fromCache,false);
      const staffClient = env.authenticatedContext('staffA').firestore();
      const missing = await assertSucceeds(getDoc(doc(staffClient,`${path}/s1`)));
      assert.equal(missing.exists(),false);
      assert.equal(missing.metadata.fromCache,false);
      const currentRules = readFileSync('../firestore.rules','utf8');
      const start = currentRules.indexOf('    match /staffAvailability/');
      const end = currentRules.indexOf('    match /catalogs/',start);
      assert.ok(start>=0 && end>start);
      const oldEnv = await initializeTestEnvironment({projectId:'demo-staff-absence-old-rules',firestore:{host,port:Number(port),rules:currentRules.slice(0,start)+currentRules.slice(end)}});
      try {
        await oldEnv.withSecurityRulesDisabled(async (context)=>{
          await setDoc(doc(context.firestore(),'users/adminA'),{role:'admin',active:true});
        });
        await assert.rejects(getDocs(collection(oldEnv.authenticatedContext('adminA').firestore(),path)),(error)=>error.code==='permission-denied');
      } finally { await oldEnv.cleanup(); }
    });
    await t.test('authentication, role, malformed input and staff references are verified', async () => {
      await rejects(setStaffAbsence(db,null,absence('2026-11-16')),'unauthenticated');
      for(const uid of ['staffA','inactive','missing']) await rejects(setStaffAbsence(db,uid,absence('2026-11-16')),'permission-denied');
      for(const changes of [{date:'2026-02-30'},{periods:[]},{periods:['morning','morning']},{expectedVersion:-1},{active:false}]) {
        await rejects(setStaffAbsence(db,'adminA',absence('2026-11-16',changes)),'invalid-argument');
      }
      await rejects(setStaffAbsence(db,'adminA',absence('2026-11-16',{staffId:'unknown'})),'failed-precondition');
    });
    await t.test('AM/PM and whole-day cancellation preserve other periods, dates, users and weekly master', async () => {
      const user = (await db.doc('users/staffA').get()).data();
      const master = (await db.doc('catalogs/absence-v1/staff/s1').get()).data();
      await setStaffAbsence(db,'adminA',absence('2026-11-16'));
      await setStaffAbsence(db,'adminA',absence('2026-11-17',{periods:['morning','afternoon']}));
      await setStaffAbsence(db,'adminA',absence('2026-11-16',{periods:['afternoon'],expectedVersion:1}));
      let result = await setStaffAbsence(db,'adminA',absence('2026-11-16',{absent:false,expectedVersion:2}));
      assert.deepEqual(result,{version:3,unavailablePeriods:['afternoon']});
      result = await setStaffAbsence(db,'adminA',absence('2026-11-16',{periods:['morning','afternoon'],absent:false,expectedVersion:3}));
      assert.deepEqual(result,{version:4,unavailablePeriods:[]});
      assert.deepEqual((await ref('2026-11-17').get()).data().unavailablePeriods,['afternoon','morning']);
      assert.deepEqual((await db.doc('users/staffA').get()).data(),user);
      assert.deepEqual((await db.doc('catalogs/absence-v1/staff/s1').get()).data(),master);
      assert.equal((await db.collection('schedules').get()).size,0);
    });
    await t.test('same request retries once; two administrators with same version cannot overwrite each other', async () => {
      const request = absence('2026-11-18');
      const results = await Promise.all([setStaffAbsence(db,'adminA',request),setStaffAbsence(db,'adminA',request)]);
      assert.deepEqual(results[0],results[1]);
      assert.equal((await ref(request.date).collection('commits').get()).size,1);
      await rejects(setStaffAbsence(db,'adminA',{...request,absent:false}),'already-exists');
      await rejects(setStaffAbsence(db,'adminB',request),'already-exists');
      const race = await Promise.allSettled([setStaffAbsence(db,'adminA',absence('2026-11-19')),setStaffAbsence(db,'adminB',absence('2026-11-19',{periods:['afternoon']}))]);
      assert.equal(race.filter((r)=>r.status==='fulfilled').length,1);
      assert.equal(race.find((r)=>r.status==='rejected').reason.code,'aborted');
      assert.equal((await ref('2026-11-19').get()).data().version,1);
    });
    await t.test('absent staff blocks confirmation atomically; other date/period still confirms', async () => {
      await setStaffAbsence(db,'adminA',absence('2026-11-20'));
      const request = schedule('2026-11-20');
      await rejects(confirm(db,'adminA',request),'failed-precondition');
      assert.equal((await db.doc(`schedules/${request.date}_morning`).get()).exists,false);
      assert.equal((await db.doc(`staffSchedules/s1/days/${request.date}_morning`).get()).exists,false);
      assert.equal((await db.collection(`schedules/${request.date}_morning/commits`).get()).size,0);
      await confirm(db,'adminA',operationRequest(catalog,request.date,'afternoon','absence-v1',randomUUID()));
      await confirm(db,'adminA',schedule('2026-11-21'));
    });
    await t.test('absence keeps historical confirmed data, prevents fresh confirmation until cancellation', async () => {
      const request = schedule('2026-11-23');
      await confirm(db,'adminA',request);
      const saved = (await db.doc('schedules/2026-11-23_morning').get()).data();
      const projection = (await db.doc('staffSchedules/s1/days/2026-11-23_morning').get()).data();
      await setStaffAbsence(db,'adminB',absence(request.date));
      assert.deepEqual((await db.doc('schedules/2026-11-23_morning').get()).data(),saved);
      assert.deepEqual((await db.doc('staffSchedules/s1/days/2026-11-23_morning').get()).data(),projection);
      // A receipt retry acknowledges history only, never creates another confirmation.
      assert.equal((await confirm(db,'adminA',request)).version,1);
      await rejects(confirm(db,'adminA',{...request,requestId:randomUUID(),expectedVersion:1}),'failed-precondition');
      await setStaffAbsence(db,'adminB',absence(request.date,{absent:false,expectedVersion:1}));
      await rejects(confirm(db,'adminA',{...request,requestId:randomUUID(),expectedVersion:1,expectedAvailabilityVersions:Object.fromEntries(request.routes.map((r)=>[r.staffId,0]))}),'aborted');
      assert.equal((await confirm(db,'adminA',{...request,requestId:randomUUID(),expectedVersion:1,expectedAvailabilityVersions:Object.fromEntries(request.routes.map((r)=>[r.staffId,r.staffId==='s1'?2:0]))})).version,2);
    });
    await t.test('simultaneous absence and confirmation serialize without partial schedule/projection commits', async () => {
      for(const date of ['2026-11-24','2026-11-25','2026-11-26']) {
        const results = await Promise.allSettled([setStaffAbsence(db,'adminA',absence(date)),confirm(db,'adminB',schedule(date))]);
        assert.equal(results[0].status,'fulfilled');
        if(results[1].status==='rejected') assert.equal(results[1].reason.code,'failed-precondition');
        assert.deepEqual((await ref(date).get()).data().unavailablePeriods,['morning']);
        const saved = await db.doc(`schedules/${date}_morning`).get();
        const own = await db.doc(`staffSchedules/s1/days/${date}_morning`).get();
        assert.equal(saved.exists,own.exists);
        if(saved.exists) { assert.equal(saved.data().version,1); assert.equal(own.data().version,1); }
        await rejects(confirm(db,'adminB',schedule(date,{expectedVersion:saved.exists?1:0})),'failed-precondition');
      }
    });
    await t.test('all reads precede writes, including transaction retries; corrupt absence fails closed', async () => {
      const checked = {doc:(path)=>db.doc(path),runTransaction:(callback)=>db.runTransaction((tx)=>{
        let wrote=false;
        const proxy=new Proxy(tx,{get(target,name){
          if(['get','getAll'].includes(name)) return (...args)=>{assert.equal(wrote,false,'read after write');return target[name](...args);};
          if(['set','create','delete','update'].includes(name)) return (...args)=>{wrote=true;target[name](...args);return proxy;};
          const value=target[name]; return typeof value==='function'?value.bind(target):value;
        }});
        return callback(proxy);
      })};
      await setStaffAbsence(checked,'adminA',absence('2026-11-27'));
      await confirm(checked,'adminA',schedule('2026-11-28'));
      await ref('2026-11-30').set({schemaVersion:1,date:'2026-11-30',staffId:'s1',version:1,unavailablePeriods:['invalid']});
      await rejects(confirm(db,'adminA',schedule('2026-11-30')),'failed-precondition');
    });
    await t.test('A-2 20/80 whole-course handoff: absence, atomic confirmation, own staff reads, retry and date/period isolation', async () => {
      const date='2026-12-07';
      const original=schedule(date);
      await confirm(db,'adminA',original);
      await confirm(db,'adminA',operationRequest(catalog,date,'afternoon','absence-v1',randomUUID()));
      await confirm(db,'adminA',schedule('2026-12-08'));
      const afternoon=(await db.doc(`schedules/${date}_afternoon`).get()).data();
      const nextDay=(await db.doc('schedules/2026-12-08_morning').get()).data();
      await setStaffAbsence(db,'adminA',absence(date,{periods:['morning','afternoon']}));
      await rejects(confirm(db,'adminA',schedule(date,{expectedVersion:1})),'failed-precondition');
      const handoff=structuredClone(original);
      handoff.expectedVersion=1;handoff.requestId=randomUUID();handoff.routes[0].staffId='s3';
      handoff.expectedAvailabilityVersions=Object.fromEntries(handoff.routes.map((r)=>[r.staffId,0]));
      const occupied=structuredClone(handoff);occupied.requestId=randomUUID();occupied.routes[0].staffId='s2';
      await rejects(confirm(db,'adminB',occupied),'invalid-argument');
      // Target availability can change after the administrator reviewed a draft.
      await setStaffAbsence(db,'adminB',absence(date,{staffId:'s3'}));
      await rejects(confirm(db,'adminA',handoff),'failed-precondition');
      await setStaffAbsence(db,'adminB',absence(date,{staffId:'s3',absent:false,expectedVersion:1}));
      await rejects(confirm(db,'adminA',handoff),'aborted');
      handoff.expectedAvailabilityVersions.s3=2;handoff.requestId=randomUUID();
      const saved=await Promise.all([confirm(db,'adminA',handoff),confirm(db,'adminA',handoff)]);
      assert.ok(saved.every((r)=>r.version===2));
      assert.equal((await db.collection(`schedules/${date}_morning/commits`).get()).size,2);
      const canonical=(await db.doc(`schedules/${date}_morning`).get()).data();
      assert.equal(canonical.routes.length,19);
      assert.equal(canonical.routes.flatMap((r)=>r.passengerIds).length,80);
      assert.deepEqual(canonical.routes[0],{...original.routes[0],staffId:'s3'});
      assert.deepEqual((await db.doc(`schedules/${date}_afternoon`).get()).data(),afternoon);
      assert.deepEqual((await db.doc('schedules/2026-12-08_morning').get()).data(),nextDay);
      assert.equal((await db.doc(`staffSchedules/s1/days/${date}_morning`).get()).exists,false);
      await db.doc('users/reserve').set({role:'staff',staffId:'s3',active:true});
      const reserve=env.authenticatedContext('reserve').firestore();
      const own=await assertSucceeds(getDoc(doc(reserve,`staffSchedules/s3/days/${date}_morning`)));
      assert.deepEqual(own.data().routes,[{...original.routes[0],staffId:'s3'}]);
      await assertFails(getDoc(doc(reserve,`staffSchedules/s2/days/${date}_morning`)));
      const oldClient=env.authenticatedContext('staffA').firestore();
      assert.equal((await assertSucceeds(getDoc(doc(oldClient,`staffSchedules/s1/days/${date}_morning`)))).exists(),false);
      assert.equal((await assertSucceeds(getDoc(doc(oldClient,`staffSchedules/s1/days/${date}_afternoon`)))).exists(),true);
      // The afternoon remains unresolved after a morning-only handoff.
      await rejects(confirm(db,'adminA',operationRequest(catalog,date,'afternoon','absence-v1',randomUUID(),1)),'failed-precondition');
      await rejects(confirm(db,'staffA',{...handoff,requestId:randomUUID(),expectedVersion:2}),'permission-denied');
      await rejects(confirm(db,'adminB',{...handoff,requestId:randomUUID()}),'aborted');
    });
    await t.test('rules allow admin date lists / staff own reads only; every client write is denied', async () => {
      const admin = env.authenticatedContext('adminA').firestore();
      const staff = env.authenticatedContext('staffA').firestore();
      const anon = env.unauthenticatedContext().firestore();
      const path = 'staffAvailability/2026-11-23/staff/s1';
      await assertSucceeds(getDocs(collection(admin,'staffAvailability/2026-11-23/staff')));
      await assertSucceeds(getDoc(doc(staff,path)));
      await assertFails(getDoc(doc(staff,'staffAvailability/2026-11-23/staff/s2')));
      await assertFails(getDocs(collection(staff,'staffAvailability/2026-11-23/staff')));
      await assertFails(getDoc(doc(anon,path)));
      for(const client of [admin,staff,anon]) await assertFails(setDoc(doc(client,path),{unavailablePeriods:[]}));
      const receipt = (await ref('2026-11-23').collection('commits').get()).docs[0].id;
      await assertSucceeds(getDoc(doc(admin,`${path}/commits/${receipt}`)));
      await assertFails(getDoc(doc(staff,`${path}/commits/${receipt}`)));
    });
  } finally { await env.cleanup(); await deleteApp(app); }
});
