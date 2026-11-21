'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {readFileSync} = require('node:fs');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, collection, query, where, getDoc, getDocs, setDoc, deleteDoc, serverTimestamp, Timestamp, Bytes} = require('firebase/firestore');
const {registerCatalog} = require('../../tools/fictional_catalog.cjs');
const {operationsCatalog, operationRequest} = require('../../tools/operations_fixture.cjs');
const {confirm} = require('../schedule-service');
const {setStaffAbsence} = require('../staff-absence-service');

if (process.env.GCLOUD_PROJECT !== 'demo-senior-transport' || !/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
  throw new Error('Loopback demo Emulator required');
}
test('photo attendance uses confirmed assignments and immutable server timestamps (20 staff / 80 passengers)', async (t) => {
  const projectId = 'demo-photo-attendance';
  const app = initializeApp({projectId}, projectId);
  const db = getFirestore(app);
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const env = await initializeTestEnvironment({projectId, firestore:{host, port:Number(port), rules:readFileSync('../firestore.rules', 'utf8')}});
  const catalog = operationsCatalog();
  const version = 'photo-v1', date = '2026-11-16';
  const routeId = catalog.baseRoutes.find((r) => r.staffId === 's1' && r.period === 'morning').id;
  const context = (uid) => env.authenticatedContext(uid).firestore();
  const staff = context('photo-staff'), other = context('photo-other'), admin = context('photo-admin');
  const path = (kind='start', day=date, route=routeId) => `attendance/s1/records/${day}_morning_${route}_${kind}`;
  const photo = () => ({staffId:'s1',uid:'photo-staff',date,period:'morning',routeId,kind:'start',registeredAt:serverTimestamp(),photo:Bytes.fromUint8Array(new Uint8Array([255,216,255,217])),contentType:'image/jpeg'});
  try {
    await registerCatalog(db,version,catalog);
    for (const [uid,profile] of Object.entries({
      'photo-admin':{role:'admin',active:true}, 'photo-staff':{role:'staff',staffId:'s1',active:true},
      'photo-other':{role:'staff',staffId:'s2',active:true}, 'photo-inactive':{role:'staff',staffId:'s1',active:false},
    })) await db.doc(`users/${uid}`).set(profile);
    await confirm(db,'photo-admin',operationRequest(catalog,date,'morning',version,randomUUID()));
    await confirm(db,'photo-admin',operationRequest(catalog,date,'afternoon',version,randomUUID()));
    await t.test('missing records are an empty authorized query; end requires start', async () => {
      const records = query(collection(staff,'attendance/s1/records'),where('date','==',date),where('period','==','morning'));
      assert.equal((await assertSucceeds(getDocs(records))).empty,true);
      await assertFails(setDoc(doc(staff,path('end')),{...photo(),kind:'end'}));
    });
    await t.test('wrong roles, identities, unconfirmed dates/periods/courses cannot upload', async () => {
      for (const client of [admin,other,context('photo-inactive'),env.unauthenticatedContext().firestore()]) {
        await assertFails(setDoc(doc(client,path()),photo()));
      }
      for (const [overrides,id] of [
        [{date:'2026-11-17'},path('start','2026-11-17')],
        [{period:'afternoon'},path().replace('_morning_','_afternoon_')],
        [{routeId:'morning-wrong'},path('start',date,'morning-wrong')],
        [{uid:'photo-admin'},path()], [{staffId:'s2'},path()],
      ]) await assertFails(setDoc(doc(staff,id),{...photo(),...overrides}));
    });
    await t.test('client timestamps, unknown fields, empty and oversized images are rejected', async () => {
      for (const overrides of [
        {registeredAt:Timestamp.fromMillis(0)}, {contentType:'text/plain'}, {extra:'blocked'},
        {photo:Bytes.fromUint8Array(new Uint8Array())}, {photo:Bytes.fromUint8Array(new Uint8Array(184321))},
      ]) await assertFails(setDoc(doc(staff,path()),{...photo(),...overrides}));
    });
    await t.test('start and end photos store a real server registration time, then survive re-reads', async () => {
      const before = Date.now() - 10000;
      await assertSucceeds(setDoc(doc(staff,path()),photo()));
      const saved = (await assertSucceeds(getDoc(doc(staff,path())))).data();
      assert.ok(saved.registeredAt.toMillis() >= before && saved.registeredAt.toMillis() <= Date.now()+10000);
      assert.equal(saved.staffId,'s1'); assert.equal(saved.date,date); assert.equal(saved.routeId,routeId);
      assert.equal(saved.photo.toUint8Array().length,4);
      const afternoonRoute=catalog.baseRoutes.find(r=>r.staffId==='s1'&&r.period==='afternoon').id;
      const afternoonPath=`attendance/s1/records/${date}_afternoon_${afternoonRoute}_end`;
      await assertSucceeds(setDoc(doc(staff,afternoonPath),{...photo(),period:'afternoon',routeId:afternoonRoute,kind:'end'}));
      assert.ok((await getDoc(doc(staff,afternoonPath))).data().registeredAt.toMillis() >= saved.registeredAt.toMillis());
    });
    await t.test('afternoon end succeeds without morning start, and afternoon start is denied',async()=>{
      const day='2026-11-20';
      await confirm(db,'photo-admin',operationRequest(catalog,day,'afternoon',version,randomUUID()));
      const route=catalog.baseRoutes.find(r=>r.staffId==='s1'&&r.period==='afternoon').id;
      const value={...photo(),date:day,period:'afternoon',routeId:route,kind:'end'};
      await assertSucceeds(setDoc(doc(staff,`attendance/s1/records/${day}_afternoon_${route}_end`),value));
      await assertFails(setDoc(doc(staff,`attendance/s1/records/${day}_afternoon_${route}_start`),{...value,kind:'start'}));
      assert.equal((await db.doc(path('start',day)).get()).exists,false);
    });
    await t.test('administrator sees selected staff records; another staff member and anonymous users cannot', async () => {
      assert.equal((await assertSucceeds(getDocs(collection(admin,'attendance/s1/records')))).size,3);
      await assertSucceeds(getDoc(doc(staff,path())));
      for (const client of [other,env.unauthenticatedContext().firestore()]) {
        await assertFails(getDoc(doc(client,path())));
        await assertFails(getDocs(collection(client,'attendance/s1/records')));
      }
      await assertFails(getDocs(collection(staff,'attendance/s2/records')));
    });
    await t.test('duplicates cannot overwrite the first photo or timestamp; clients including admins cannot delete', async () => {
      const original = (await db.doc(path()).get()).data();
      await assertFails(setDoc(doc(staff,path()),photo()));
      for (const client of [staff,admin]) await assertFails(deleteDoc(doc(client,path())));
      assert.deepEqual((await db.doc(path()).get()).data(),original);
    });
    await t.test('absence blocks old confirmed courses, but existing photos remain readable', async () => {
      const next = '2026-11-17';
      await confirm(db,'photo-admin',operationRequest(catalog,next,'morning',version,randomUUID()));
      await setStaffAbsence(db,'photo-admin',{date:next,staffId:'s1',periods:['morning'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion:version});
      await assertFails(setDoc(doc(staff,path('start',next)),{...photo(),date:next}));
      await assertSucceeds(getDoc(doc(staff,path())));
    });
    await t.test('reassignment removes the previous staff write access without removing historical photos', async () => {
      const next = '2026-11-18';
      const request = operationRequest(catalog,next,'morning',version,randomUUID());
      await confirm(db,'photo-admin',request);
      await assertSucceeds(setDoc(doc(staff,path('start',next)),{...photo(),date:next}));
      const replacement = request.routes.map((r) => r.staffId === 's1' ? {...r,staffId:'s3'} : r);
      // s3 is the fixture's unassigned reserve employee.
      await confirm(db,'photo-admin',{...request,routes:replacement,expectedVersion:1,requestId:randomUUID()});
      await assertFails(setDoc(doc(staff,path('end',next)),{...photo(),date:next,kind:'end'}));
      await assertSucceeds(getDoc(doc(staff,path('start',next))));
    });
  } finally { await env.cleanup(); await deleteApp(app); }
});
