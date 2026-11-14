"use strict";
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID, randomBytes } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { spawnSync } = require('node:child_process');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, getDocs, collection, onSnapshot } = require('firebase/firestore');
const { fictionalCatalog, registerCatalog } = require('../../tools/fictional_catalog.cjs');
const { confirm } = require('../schedule-service');

const projectId = 'demo-senior-transport';
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
    process.env.GCLOUD_PROJECT !== projectId) throw new Error('Emulator-only tests require demo-senior-transport');

test('developer registration tools reject real projects before initializing any Firebase client', () => {
  for (const tool of ['seed_emulator.cjs', 'create_emulator_user.cjs']) {
    const attempt = spawnSync(process.execPath, [`../tools/${tool}`], {encoding: 'utf8',
      env: {...process.env, GCLOUD_PROJECT: 'not-a-demo-project', FIRESTORE_EMULATOR_HOST: '', FIREBASE_AUTH_EMULATOR_HOST: ''}});
    assert.notEqual(attempt.status, 0);
    assert.match(attempt.stderr, /only supports|Only loopback/);
  }
});

test('Firestore + Auth + callable Emulator integration, 40 staff / 79 passengers', async (t) => {
  const app = initializeApp({projectId});
  const db = getFirestore(app);
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const environment = await initializeTestEnvironment({projectId, firestore: {
    host, port: Number(port), rules: readFileSync('../firestore.rules', 'utf8'),
  }});
  const catalog = fictionalCatalog(true);
  assert.equal(catalog.staff.length, 40);
  assert.equal(catalog.passengers.length, 79);
  await registerCatalog(db, 'scale-v1', catalog);
  await t.test('developer CLIs register fictional catalog and validate employee binding locally', async () => {
    const seeded = spawnSync(process.execPath, ['../tools/seed_emulator.cjs', '--version=tool-v1', '--scale'], {encoding: 'utf8', env: process.env});
    assert.equal(seeded.status, 0, seeded.stderr);
    assert.equal((await db.doc('catalogs/tool-v1').get()).data().ready, true);
    const userEnvironment = {...process.env, EMULATOR_USER_EMAIL: `${randomUUID()}@example.invalid`, EMULATOR_USER_PASSWORD: randomBytes(24).toString('base64url')};
    const created = spawnSync(process.execPath, ['../tools/create_emulator_user.cjs', 'staff', 's40'], {encoding: 'utf8', env: userEnvironment});
    assert.equal(created.status, 0, created.stderr);
    const invalidBinding = spawnSync(process.execPath, ['../tools/create_emulator_user.cjs', 'staff', 'unknown'], {encoding: 'utf8', env: userEnvironment});
    assert.notEqual(invalidBinding.status, 0);
    await db.doc('settings/schedules').set({catalogVersion: 'scale-v1'});
  });
  async function account(role, staffId) {
    const email = `${randomUUID()}@example.invalid`;
    const password = randomBytes(24).toString('base64url');
    const authUrl = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts`;
    const signup = await fetch(`${authUrl}:signUp?key=emulator`, {method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({email, password, returnSecureToken: true})});
    assert.equal(signup.status, 200);
    const created = await signup.json();
    await db.doc(`users/${created.localId}`).set({role, active: true, ...(staffId ? {staffId} : {})});
    const login = await fetch(`${authUrl}:signInWithPassword?key=emulator`, {method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({email, password, returnSecureToken: true})});
    assert.equal(login.status, 200);
    return login.json();
  }
  const admin = await account('admin');
  const staff = await account('staff', 's1');
  const replacement = await account('staff', 's3');
  const invalid = await account('staff', 'not-a-staff');
  const adminClient = environment.authenticatedContext(admin.localId).firestore();
  const staffClient = environment.authenticatedContext(staff.localId).firestore();
  const replacementClient = environment.authenticatedContext(replacement.localId).firestore();
  const invalidClient = environment.authenticatedContext(invalid.localId).firestore();
  function request(date = '2026-11-14', period = 'morning') {
    const start = period === 'morning' ? 480 : 960;
    return {date, period, catalogVersion: 'scale-v1', expectedVersion: 0, requestId: randomUUID(), absentIds: [], excludedIds: [],
      routes: catalog.baseRoutes.filter((r) => r.period === period).map((r) => ({
        baseRouteId: r.id, staffId: r.staffId, vehicleId: r.vehicleId, passengerIds: [...r.passengerIds],
        estimatedVisitMinutes: Object.fromEntries(r.passengerIds.map((id, i) => [id, start + 10 + i * 10])), startMinute: start, endMinute: start + 90,
      }))};
  }
  async function call(data, user = admin) {
    const response = await fetch(`http://${process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001'}/${projectId}/asia-northeast3/confirmSchedule`, {
      method: 'POST', headers: {'Content-Type': 'application/json', ...(user ? {Authorization: `Bearer ${user.idToken}`} : {})},
      body: JSON.stringify({data}),
    });
    const body = await response.json();
    return {ok: response.ok, status: response.status, ...body};
  }
  let first;
  try {
    await t.test('callable upgrades legacy estimates, preserves mixed sources in own projection, and rejects invalid sources atomically', async () => {
      const payload = request('2027-01-04');
      const initial = await call(payload);
      assert.equal(initial.ok, true, JSON.stringify(initial.error));
      assert.equal(initial.result.version, 1);
      const id = `${payload.date}_${payload.period}`;
      const legacy = (await db.doc(`schedules/${id}`).get()).data();
      assert.equal(legacy.routes[0].estimatedVisitSources, undefined);
      payload.expectedVersion = 1;
      payload.requestId = randomUUID();
      for (const route of payload.routes) {
        route.estimatedVisitSources = Object.fromEntries(route.passengerIds.map((id, i) => [id, i === 0 ? 'manual' : 'fixedInterval']));
      }
      const committed = await call(payload);
      assert.equal(committed.ok, true, JSON.stringify(committed.error));
      assert.equal(committed.result.version, 2);
      assert.equal((await call(payload)).result.version, 2); // Retry is idempotent.
      const saved = (await db.doc(`schedules/${id}`).get()).data();
      const own = (await assertSucceeds(getDoc(doc(staffClient, `staffSchedules/s1/days/${id}`)))).data();
      const ownStored = (await db.doc(`staffSchedules/s1/days/${id}`).get()).data();
      assert.deepEqual(saved.routes, payload.routes);
      assert.deepEqual(own.routes, payload.routes.filter(r => r.staffId === 's1'));
      assert.deepEqual(own.routes[0].estimatedVisitMinutes, legacy.routes[0].estimatedVisitMinutes);
      await assertFails(getDoc(doc(replacementClient, `staffSchedules/s1/days/${id}`)));
      const invalid = structuredClone(payload);
      invalid.expectedVersion = 2; invalid.requestId = randomUUID();
      invalid.routes[0].estimatedVisitSources.p1 = 'invalid-source';
      assert.equal((await call(invalid)).error.status, 'INVALID_ARGUMENT');
      assert.deepEqual((await db.doc(`schedules/${id}`).get()).data(), saved);
      assert.deepEqual((await db.doc(`staffSchedules/s1/days/${id}`).get()).data(), ownStored);
      assert.equal((await db.doc(`schedules/${id}/commits/${invalid.requestId}`).get()).exists, false);
    });
    await t.test('anonymous/staff cannot confirm; both roles authenticate through Auth emulator', async () => {
      assert.equal((await call(request(), null)).error.status, 'UNAUTHENTICATED');
      assert.equal((await call(request(), staff)).error.status, 'PERMISSION_DENIED');
      await assertFails(updateDoc(doc(staffClient, `users/${staff.localId}`), {role:'admin'}));
      await assertFails(setDoc(doc(adminClient, 'schedules/forged'), request()));
      await assertFails(setDoc(doc(staffClient, 'catalogs/forged'), {ready: true}));
    });
    await t.test('large schedule commits and reloads with staff-only projections', async () => {
      first = request();
      const result = await call(first);
      assert.equal(result.ok, true, JSON.stringify(result.error));
      assert.equal(result.result.version, 1);
      assert.equal((await db.doc('schedules/2026-11-14_morning').get()).data().routes.length, 39);
      const own = await assertSucceeds(getDoc(doc(staffClient, 'staffSchedules/s1/days/2026-11-14_morning')));
      assert.deepEqual(own.data().catalog.passengers.map((p) => p.id), ['p1','p2','p3']);
      assert.equal(own.data().catalog.staff.length, 1);
      await assertFails(getDoc(doc(staffClient, 'schedules/2026-11-14_morning')));
      await assertFails(getDoc(doc(staffClient, 'staffSchedules/s2/days/2026-11-14_morning')));
      await assertFails(getDocs(collection(staffClient, 'catalogs/scale-v1/passengers')));
      await assertSucceeds(getDoc(doc(staffClient, 'catalogs/scale-v1/staff/s1')));
      await assertFails(getDoc(doc(staffClient, 'catalogs/scale-v1/staff/s2')));
      await assertFails(getDoc(doc(invalidClient, 'staffSchedules/not-a-staff/days/2026-11-14_morning')));
    });
    await t.test('reassignment deletes previous staff projection atomically, preserves other date/period', async () => {
      assert.equal((await call(request('2026-11-15'))).ok, true);
      assert.equal((await call(request('2026-11-14', 'afternoon'))).ok, true);
      const moved = structuredClone(first);
      moved.expectedVersion = 1; moved.requestId = randomUUID(); moved.absentIds = ['p2'];
      moved.routes[0].staffId = 's3';
      moved.routes[0].passengerIds = ['p1','p3','p4'];
      moved.routes[0].estimatedVisitMinutes = {p1:490,p3:500,p4:510};
      moved.routes[1].passengerIds = ['p5']; moved.routes[1].estimatedVisitMinutes = {p5:490};
      assert.equal((await call(moved)).ok, true);
      assert.equal((await db.doc('staffSchedules/s1/days/2026-11-14_morning').get()).exists, false);
      const projection = await assertSucceeds(getDoc(doc(replacementClient, 'staffSchedules/s3/days/2026-11-14_morning')));
      assert.deepEqual(projection.data().routes[0].passengerIds, ['p1','p3','p4']);
      assert.equal((await db.doc('staffSchedules/s1/days/2026-11-15_morning').get()).exists, true);
      assert.equal((await db.doc('staffSchedules/s1/days/2026-11-14_afternoon').get()).exists, true);
      const missing = await assertSucceeds(getDoc(doc(staffClient, 'staffSchedules/s1/days/2026-11-14_morning')));
      assert.equal(missing.exists(), false);
      const updated = {...moved, requestId: randomUUID(), expectedVersion: 2, routes: structuredClone(moved.routes)};
      updated.routes[0].estimatedVisitMinutes.p1 = 491;
      const realtime = new Promise((resolve, reject) => {
        const timer = setTimeout(() => { unsubscribe(); reject(new Error('Realtime update timed out')); }, 12000);
        const unsubscribe = onSnapshot(doc(replacementClient, 'staffSchedules/s3/days/2026-11-14_morning'), (value) => {
          if (value.data()?.version === 3) { clearTimeout(timer); unsubscribe(); resolve(value.data()); }
        }, reject);
      });
      assert.equal((await call(updated)).ok, true);
      assert.equal((await realtime).routes[0].estimatedVisitMinutes.p1, 491);
    });
    await t.test('concurrent same request is idempotent; changed payload cannot reuse request ID', async () => {
      const payload = request('2026-11-16');
      const results = await Promise.all([call(payload), call(payload)]);
      assert.ok(results.every((r) => r.ok && r.result.version === 1));
      assert.equal((await db.collection('schedules/2026-11-16_morning/commits').get()).size, 1);
      payload.routes[0].estimatedVisitMinutes.p1 = 491;
      assert.equal((await call(payload)).error.status, 'ALREADY_EXISTS');
    });
    await t.test('concurrent different administrators cannot overwrite an unseen version', async () => {
      const secondAdmin = await account('admin');
      const a = {...request('2026-11-16'), expectedVersion:1};
      const b = structuredClone(a); b.requestId = randomUUID(); b.routes[0].estimatedVisitMinutes.p1 = 491;
      const results = await Promise.all([call(a), call(b, secondAdmin)]);
      assert.equal(results.filter((r) => r.ok).length, 1);
      assert.equal(results.find((r) => !r.ok).error.status, 'ABORTED');
      assert.equal((await db.doc('schedules/2026-11-16_morning').get()).data().version, 2);
    });
    await t.test('invalid duplicate/capacity/time/availability payloads never partially write', async () => {
      const cases = [
        (p) => { p.routes[1].staffId = p.routes[0].staffId; },
        (p) => { p.routes[0].passengerIds.push('p4'); p.routes[0].estimatedVisitMinutes.p4 = 520; },
        (p) => { p.routes[0].estimatedVisitMinutes.p2 = -1; },
        (p) => { p.routes[0].staffId = 'unknown'; },
        (p) => { p.routes[0].staffId = 's3'; },
      ];
      for (const mutate of cases) {
        const payload = request('2026-11-20'); // Friday: s3 unavailable.
        mutate(payload);
        const result = await call(payload);
        assert.equal(result.error.status, 'INVALID_ARGUMENT');
        assert.equal((await db.doc('schedules/2026-11-20_morning').get()).exists, false);
        assert.equal((await db.doc('staffSchedules/s1/days/2026-11-20_morning').get()).exists, false);
      }
    });
    await t.test('all transaction reads precede writes, including retried calls', async () => {
      const instrumented = Object.create(db);
      instrumented.runTransaction = (callback) => db.runTransaction((tx) => {
        let writing = false;
        const wrapped = new Proxy(tx, {get(target, key) {
          if (['get','getAll'].includes(key)) return (...args) => { assert.equal(writing, false); return target[key](...args); };
          if (['set','create','update','delete'].includes(key)) return (...args) => { writing = true; return target[key](...args); };
          return Reflect.get(target, key);
        }});
        return callback(wrapped);
      });
      const payload = request('2026-11-21');
      assert.equal((await confirm(instrumented, admin.localId, payload)).version, 1);
      assert.equal((await confirm(instrumented, admin.localId, payload)).version, 1);
    });
    await t.test('setStaffAbsence callable authorizes admin only and persists date-scoped status', async () => {
      const data = {date:'2026-12-01',staffId:'s1',periods:['morning','afternoon'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion:'scale-v1'};
      async function callAbsence(user) {
        const response = await fetch(`http://${process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001'}/${projectId}/asia-northeast3/setStaffAbsence`, {
          method:'POST',headers:{'Content-Type':'application/json',...(user?{Authorization:`Bearer ${user.idToken}`}:{})},body:JSON.stringify({data}),
        });
        return response.json();
      }
      assert.equal((await callAbsence(null)).error.status,'UNAUTHENTICATED');
      assert.equal((await callAbsence(staff)).error.status,'PERMISSION_DENIED');
      assert.deepEqual((await callAbsence(admin)).result,{version:1,unavailablePeriods:['afternoon','morning']});
      assert.equal((await db.doc('staffAvailability/2026-12-01/staff/s1').get()).data().updatedBy,admin.localId);
      assert.equal((await call(request('2026-12-01'))).error.status,'FAILED_PRECONDITION');
    });
    await t.test('inactive role and disabled staff mapping are denied; master baseline unchanged', async () => {
      await db.doc(`users/${admin.localId}`).update({active:false});
      assert.equal((await call(request('2026-11-22'))).error.status, 'PERMISSION_DENIED');
      await assertFails(getDoc(doc(adminClient, 'schedules/2026-11-14_morning')));
      await db.doc('catalogs/scale-v1/staff/s3').update({active:false});
      await assertFails(getDoc(doc(replacementClient, 'staffSchedules/s3/days/2026-11-14_morning')));
      assert.deepEqual((await db.doc('catalogs/scale-v1/baseRoutes/morning-a').get()).data().passengerIds, ['p1','p2','p3']);
    });
  } finally {
    await environment.cleanup();
    await db.terminate();
    await deleteApp(app);
  }
});
