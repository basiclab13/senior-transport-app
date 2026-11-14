'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { spawnSync } = require('node:child_process');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { confirm } = require('../schedule-service');
const { makePlan, registerInitialCatalog } = require('../../tools/initial-catalog-registration.cjs');
const { parseArguments } = require('../../tools/register-initial-catalog.cjs');

const fixture = JSON.parse(readFileSync(resolve(__dirname, '../../docs/fixtures/deploy-test-v2.baseline.json'), 'utf8'));
const plan = makePlan(fixture);

test('initial registration enforces target, explicit write confirmation and offline planning', () => {
  assert.equal(plan.documents.length, 15);
  assert.equal(plan.catalogVersion, 'deploy-test-v2');
  const original=JSON.parse(readFileSync(resolve(__dirname,'../../docs/fixtures/deploy-test-v1.baseline.json'),'utf8'));
  assert.deepEqual(original.collections,fixture.collections);
  assert.throws(() => makePlan(original),{code:'INVALID_MANIFEST'});
  assert.throws(() => parseArguments(['--project','senior-transport-app','--expected-catalog-version','other'],{}),/INVALID_PREVIOUS_VERSION/);
  assert.deepEqual(plan.counts, {staff:3, vehicles:3, passengers:5, baseRoutes:4});
  assert.equal(parseArguments(['--project','senior-transport-app'], {}).apply, false);
  for (const args of [[], ['--project','wrong'], ['--project','senior-transport-app','--apply'],
    ['--project','senior-transport-app','--apply','--confirm-project','wrong'],
    ['--project','senior-transport-app','--apply','--confirm-project','senior-transport-app','--dry-run'],
    ['--project','senior-transport-app','--scale'], ['--project','senior-transport-app','--project','senior-transport-app']]) {
    assert.throws(() => parseArguments(args, {}));
  }
  assert.throws(() => parseArguments(['--project','senior-transport-app'], {FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080'}));
  assert.throws(() => parseArguments(['--project','senior-transport-app'], {GCLOUD_PROJECT:'wrong'}));
  assert.throws(() => parseArguments(['--project','senior-transport-app'], {FIREBASE_CONFIG:'{"projectId":"wrong"}'}));
  assert.throws(() => parseArguments(['--emulator','--project','demo-catalog-test'], {FIRESTORE_EMULATOR_HOST:'remote:8080'}));
  const offline = spawnSync(process.execPath, [resolve(__dirname,'../../tools/register-initial-catalog.cjs'),
    '--project','senior-transport-app','--plan'], {encoding:'utf8'});
  assert.equal(offline.status, 0, offline.stderr);
  assert.equal(JSON.parse(offline.stdout).firebaseAccess, false);
  assert.equal(JSON.parse(offline.stdout).writes, false);
  for (const mutate of [
    (m) => {m.collections.staff.push({...m.collections.staff[0], id:'s4'});},
    (m) => {m.collections.baseRoutes[0].staffId='missing';},
    (m) => {m.collections.baseRoutes[0].passengerIds=['p1','p1'];},
    (m) => {m.collections.vehicles[0].passengerCapacity=1;},
    (m) => {m.collections.staff[0].active='true';},
    (m) => {m.collections.staff[0].unavailableWeekdays=[8];},
    (m) => {m.collections.baseRoutes[1].staffId='s1';},
  ]) {
    const changed = structuredClone(fixture); mutate(changed);
    assert.throws(() => makePlan(changed), {code:'INVALID_MANIFEST'});
  }
});

test('initial registration Firestore Emulator safety and recovery', async (t) => {
  const projectId = 'demo-catalog-registration';
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  assert.match(host || '', /^(localhost|127\.0\.0\.1):\d+$/);
  // An isolated demo namespace prevents interference with schedule integration tests.
  const app = initializeApp({projectId}, 'catalog-registration-tests');
  const db = getFirestore(app);
  const baseEnvironment = {...process.env, GCLOUD_PROJECT:projectId, GOOGLE_CLOUD_PROJECT:projectId,
    FIREBASE_CONFIG:JSON.stringify({projectId})};
  async function clear() {
    const response = await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {method:'DELETE'});
    assert.equal(response.status, 200);
  }
  async function absentActivation() {
    assert.equal((await db.doc(plan.parentPath).get()).exists, false);
    assert.equal((await db.doc(plan.settingsPath).get()).exists, false);
  }
  function cli(...args) {
    const output = spawnSync(process.execPath, [resolve(__dirname,'../../tools/register-initial-catalog.cjs'),
      '--emulator','--project',projectId, ...args], {encoding:'utf8', env:baseEnvironment, timeout:30000});
    assert.equal(output.error, undefined, String(output.error));
    return {exit:output.status, result:JSON.parse(output.stdout || output.stderr)};
  }
  // Instrument real Emulator transactions: reject forbidden mutations and reads after writes.
  function instrument({beforeTransaction, failAfterStage=false, failBeforeStage=false} = {}) {
    let number=0;
    return {doc:(path) => db.doc(path), collection:(path) => db.collection(path),
      async runTransaction(callback) {
        number++;
        if (beforeTransaction) await beforeTransaction(number);
        if (failBeforeStage && number === 1) throw new Error('sensitive exception must never be logged');
        const value = await db.runTransaction(async (tx) => {
          let writing=false;
          return callback({get(ref) {assert.equal(writing,false,'all reads must precede writes'); return tx.get(ref);},
            create(ref,data) {
              writing=true;
              assert.ok(plan.documents.some((d) => d.path === ref.path) || [plan.parentPath,plan.settingsPath].includes(ref.path));
              return tx.create(ref,data);
            }, update(ref,data) {
              writing=true;
              assert.equal(ref.path,plan.settingsPath);
              assert.deepEqual(data,plan.settingsFields);
              return tx.update(ref,data);
            }});
        });
        if (failAfterStage && number === 1) throw new Error('lost commit acknowledgement');
        return value;
      }};
  }
  try {
    await t.test('default CLI reads only; explicit apply creates 15 children then 2 metadata docs; rerun creates zero', async () => {
      await clear();
      const user={role:'staff',active:true,staffId:'s1',name:'fictional'};
      await db.doc('users/existing').create(user);
      await db.doc('schedules/2026-11-12_morning').create({sentinel:true});
      await db.doc('staffSchedules/s1/days/2026-11-12_morning').create({sentinel:true});
      const dry=cli();
      assert.equal(dry.exit,0); assert.equal(dry.result.status,'DRY_RUN_OK');
      assert.equal(dry.result.plannedChildDocuments.length,15);
      await absentActivation(); assert.equal((await db.doc(plan.documents[0].path).get()).exists,false);
      assert.equal(cli('--apply').result.errorCode,'PROJECT_CONFIRMATION_REQUIRED');
      const applied=cli('--apply','--confirm-project',projectId);
      assert.equal(applied.exit,0); assert.equal(applied.result.status,'APPLIED');
      assert.equal(applied.result.createdChildDocuments,15); assert.equal(applied.result.createdMetadataDocuments,2);
      assert.equal(applied.result.verifiedChildDocuments,15); assert.equal(applied.result.checkedActiveStaffAccounts,1);
      for (const doc of plan.documents) assert.deepEqual((await db.doc(doc.path).get()).data(),doc.data);
      const timestamps=await Promise.all(plan.documents.map(async (doc) => (await db.doc(doc.path).get()).updateTime));
      assert.deepEqual((await db.doc(plan.parentPath).get()).data(),plan.metadata);
      assert.deepEqual((await db.doc(plan.settingsPath).get()).data(),plan.settingsFields);
      const again=cli('--apply','--confirm-project',projectId).result;
      assert.equal(again.status,'ALREADY_REGISTERED'); assert.equal(again.createdChildDocuments,0);
      for (let i=0; i<plan.documents.length; i++) assert.ok((await db.doc(plan.documents[i].path).get()).updateTime.isEqual(timestamps[i]));
      assert.deepEqual((await db.doc('users/existing').get()).data(),user);
      assert.deepEqual((await db.doc('schedules/2026-11-12_morning').get()).data(),{sentinel:true});
      assert.deepEqual((await db.doc('staffSchedules/s1/days/2026-11-12_morning').get()).data(),{sentinel:true});
    });
    for (const [label, path, data, code] of [
      ['conflicting child',plan.documents[0].path,{name:'existing'},'DOCUMENT_CONFLICT'],
      ['unexpected child',`${plan.parentPath}/staff/s99`,{name:'existing'},'UNEXPECTED_DOCUMENT'],
      ['parent array',plan.parentPath,{staff:[],unavailableWeekdays:[5]},'PARENT_ARRAY_FIELD'],
      ['existing unready parent',plan.parentPath,{...plan.metadata,ready:false},'PARENT_CONFLICT'],
      ['different pointer',plan.settingsPath,{catalogVersion:'other'},'SETTINGS_CONFLICT'],
      ['premature pointer',plan.settingsPath,plan.settingsFields,'POINTER_WITHOUT_PARENT'],
      ['invalid active account','users/invalid',{active:true,role:'staff',staffId:'s40'},'STAFF_ACCOUNT_MAPPING'],
      ['missing staffId','users/invalid',{active:true,role:'staff'},'STAFF_ACCOUNT_MAPPING'],
    ]) await t.test(`${label} blocks without altering existing data`,async () => {
      await clear(); await db.doc(path).create(data);
      const before=(await db.doc(path).get()).updateTime;
      const result=await registerInitialCatalog(instrument(),plan,{apply:true});
      assert.equal(result.status,'BLOCKED'); assert.ok(result.issues.some((i) => i.code === code));
      assert.ok((await db.doc(path).get()).updateTime.isEqual(before));
      assert.equal(result.createdChildDocuments,0);
      if (path !== plan.parentPath) assert.equal((await db.doc(plan.parentPath).get()).exists,false);
    });
    await t.test('identical partial children resume; activation only after saved children verified; all reads first',async () => {
      await clear(); await db.doc(plan.documents[0].path).create(plan.documents[0].data);
      const before=(await db.doc(plan.documents[0].path).get()).updateTime;
      await db.doc('users/admin').create({active:true,role:'admin'});
      await db.doc('users/inactive').create({active:false,role:'staff',staffId:'obsolete'});
      const result=await registerInitialCatalog(instrument({beforeTransaction:async (number) => {
        await absentActivation();
        if (number === 2) for (const doc of plan.documents) assert.deepEqual((await db.doc(doc.path).get()).data(),doc.data);
      }}),plan,{apply:true});
      assert.equal(result.status,'APPLIED'); assert.equal(result.createdChildDocuments,14);
      assert.ok((await db.doc(plan.documents[0].path).get()).updateTime.isEqual(before));
    });
    await t.test('pre-stage failure is sanitized and leaves no active/partial catalog',async () => {
      await clear(); const result=await registerInitialCatalog(instrument({failBeforeStage:true}),plan,{apply:true});
      assert.equal(result.status,'APPLY_FAILED'); assert.equal(result.createdChildDocuments,null);
      assert.doesNotMatch(JSON.stringify(result),/sensitive exception/);
      await absentActivation(); assert.equal((await db.doc(plan.documents[0].path).get()).exists,false);
    });
    await t.test('completed parent and existing same-version settings preserve all existing fields',async () => {
      await clear();
      for (const doc of plan.documents) await db.doc(doc.path).create(doc.data);
      await db.doc(plan.parentPath).create(plan.metadata);
      const parentTime=(await db.doc(plan.parentPath).get()).updateTime;
      const finish=await registerInitialCatalog(instrument(),plan,{apply:true});
      assert.equal(finish.status,'APPLIED'); assert.equal(finish.createdChildDocuments,0);
      assert.equal(finish.createdMetadataDocuments,1);
      assert.ok((await db.doc(plan.parentPath).get()).updateTime.isEqual(parentTime));
      await db.doc(plan.settingsPath).update({operatorNote:'preserve'});
      const before=(await db.doc(plan.settingsPath).get()).updateTime;
      const again=await registerInitialCatalog(instrument(),plan,{apply:true});
      assert.equal(again.status,'ALREADY_REGISTERED');
      assert.ok((await db.doc(plan.settingsPath).get()).updateTime.isEqual(before));
      assert.equal((await db.doc(plan.settingsPath).get()).data().operatorNote,'preserve');
    });
    await t.test('concurrent pointer change is preserved and prevents activation',async () => {
      await clear();
      const result=await registerInitialCatalog(instrument({beforeTransaction:async (number) => {
        if (number === 2) await db.doc(plan.settingsPath).create({catalogVersion:'other'});
      }}),plan,{apply:true});
      assert.equal(result.status,'APPLY_FAILED'); assert.equal(result.errorCode,'SETTINGS_CHANGED');
      assert.equal((await db.doc(plan.parentPath).get()).exists,false);
      assert.deepEqual((await db.doc(plan.settingsPath).get()).data(),{catalogVersion:'other'});
    });
    await t.test('lost stage acknowledgement leaves inactive children and resumes without duplicates',async () => {
      await clear(); const failed=await registerInitialCatalog(instrument({failAfterStage:true}),plan,{apply:true});
      assert.equal(failed.status,'APPLY_FAILED'); assert.equal(failed.createdChildDocuments,null);
      await absentActivation();
      const resumed=await registerInitialCatalog(instrument(),plan,{apply:true});
      assert.equal(resumed.status,'APPLIED'); assert.equal(resumed.createdChildDocuments,0);
    });
    for (const pointer of [false,true]) await t.test(`v2 preserves incomplete v1 and both staff bindings (existing pointer: ${pointer})`,async () => {
      await clear();
      const oldParent='catalogs/deploy-test-v1';
      await db.doc(oldParent).create({ready:false,staff:[],operatorNote:'preserve'});
      const oldPaths=[oldParent];
      for (const doc of plan.documents.slice(0,4)) {
        const path=doc.path.replace('/deploy-test-v2/','/deploy-test-v1/');
        await db.doc(path).create(doc.data); oldPaths.push(path);
      }
      for (const [uid,staffId] of [['first','s1'],['second','s2']]) {
        await db.doc(`users/${uid}`).create({active:true,role:'staff',staffId}); oldPaths.push(`users/${uid}`);
      }
      await db.doc('schedules/2026-11-10_morning').create({catalogVersion:'deploy-test-v1',sentinel:true});
      await db.doc('staffSchedules/s1/days/2026-11-10_morning').create({catalogVersion:'deploy-test-v1',sentinel:true});
      oldPaths.push('schedules/2026-11-10_morning','staffSchedules/s1/days/2026-11-10_morning');
      const times=await Promise.all(oldPaths.map(async (path)=>(await db.doc(path).get()).updateTime));
      if (pointer) await db.doc(plan.settingsPath).create({catalogVersion:'deploy-test-v1',operatorNote:'preserve'});
      const args=pointer?['--expected-catalog-version','deploy-test-v1']:[];
      if (pointer) assert.equal(cli().result.status,'BLOCKED');
      const dry=cli(...args).result;
      assert.equal(dry.status,'DRY_RUN_OK'); assert.equal(dry.plannedChildDocuments.length,15);
      assert.equal(dry.checkedActiveStaffAccounts,2);
      const applied=await registerInitialCatalog(instrument({beforeTransaction:async(number)=>{
        assert.equal((await db.doc(plan.parentPath).get()).exists,false);
        if (pointer) assert.equal((await db.doc(plan.settingsPath).get()).data().catalogVersion,'deploy-test-v1');
        if (number === 2) for (const doc of plan.documents) assert.deepEqual((await db.doc(doc.path).get()).data(),doc.data);
      }}),plan,{apply:true,...(pointer?{expectedCatalogVersion:'deploy-test-v1'}:{})});
      assert.equal(applied.status,'APPLIED'); assert.equal(applied.createdChildDocuments,15);
      assert.equal(applied.updatedSettingsDocuments,pointer?1:0);
      if (pointer) assert.equal((await db.doc(plan.settingsPath).get()).data().operatorNote,'preserve');
      for (let i=0;i<oldPaths.length;i++) assert.ok((await db.doc(oldPaths[i]).get()).updateTime.isEqual(times[i]));
      assert.equal(cli(...args).result.status,'ALREADY_REGISTERED');
    });
    await t.test('confirmed v1 schedules retain pinned catalog; new days use v2; incomplete v1 remains blocked',async () => {
      await clear();
      for (const doc of plan.documents) await db.doc(doc.path.replace('/deploy-test-v2/','/deploy-test-v1/')).create(doc.data);
      await db.doc('catalogs/deploy-test-v1').create(plan.metadata);
      await db.doc(plan.settingsPath).create({catalogVersion:'deploy-test-v1'});
      await db.doc('users/admin').create({active:true,role:'admin'});
      function request(date,version,expectedVersion=0) {
        return {date,period:'morning',catalogVersion:version,expectedVersion,requestId:`local-${date}-${expectedVersion}`,
          absentIds:[],excludedIds:[],routes:fixture.collections.baseRoutes.filter((r)=>r.period==='morning').map((r)=>({
            baseRouteId:r.id,staffId:r.staffId,vehicleId:r.vehicleId,passengerIds:r.passengerIds,
            estimatedVisitMinutes:{},startMinute:null,endMinute:null}))};
      }
      await confirm(db,'admin',request('2026-11-16','deploy-test-v1'));
      const oldSchedule=await db.doc('schedules/2026-11-16_morning').get();
      const oldProjection=await db.doc('staffSchedules/s1/days/2026-11-16_morning').get();
      const applied=await registerInitialCatalog(instrument(),plan,{apply:true,expectedCatalogVersion:'deploy-test-v1'});
      assert.equal(applied.status,'APPLIED');
      assert.ok((await oldSchedule.ref.get()).updateTime.isEqual(oldSchedule.updateTime));
      assert.ok((await oldProjection.ref.get()).updateTime.isEqual(oldProjection.updateTime));
      await assert.rejects(confirm(db,'admin',request('2026-11-16','deploy-test-v2',1)),{code:'failed-precondition'});
      await confirm(db,'admin',request('2026-11-16','deploy-test-v1',1));
      await confirm(db,'admin',request('2026-11-17','deploy-test-v2'));
      assert.equal((await oldSchedule.ref.get()).data().catalogVersion,'deploy-test-v1');
      assert.equal((await db.doc('schedules/2026-11-17_morning').get()).data().catalogVersion,'deploy-test-v2');
      await db.doc('catalogs/deploy-test-v1').update({ready:false});
      await assert.rejects(confirm(db,'admin',request('2026-11-16','deploy-test-v1',2)),{code:'failed-precondition'});
      assert.equal((await oldSchedule.ref.get()).data().version,2);
    });
    await t.test('expected predecessor must exist and remain unchanged including other settings fields',async () => {
      await clear();
      const missing=await registerInitialCatalog(instrument(),plan,{apply:true,expectedCatalogVersion:'deploy-test-v1'});
      assert.equal(missing.status,'BLOCKED'); await absentActivation();
      await db.doc(plan.settingsPath).create({catalogVersion:'deploy-test-v1',operatorNote:'initial'});
      const raced=await registerInitialCatalog(instrument({beforeTransaction:async(number)=>{
        if (number === 2) await db.doc(plan.settingsPath).update({operatorNote:'concurrent'});
      }}),plan,{apply:true,expectedCatalogVersion:'deploy-test-v1'});
      assert.equal(raced.errorCode,'SETTINGS_CHANGED');
      assert.equal((await db.doc(plan.parentPath).get()).exists,false);
      assert.deepEqual((await db.doc(plan.settingsPath).get()).data(),{catalogVersion:'deploy-test-v1',operatorNote:'concurrent'});
    });
    for (const accountRace of [false,true]) await t.test(`concurrent ${accountRace?'staff binding':'child data'} change prevents activation`,async () => {
      await clear();
      const result=await registerInitialCatalog(instrument({beforeTransaction:async (number) => {
        if (number === 2) {
          if (accountRace) await db.doc('users/racing').create({active:true,role:'staff',staffId:'missing'});
          else await db.doc(plan.documents[0].path).update({name:'concurrent edit'});
        }
      }}),plan,{apply:true});
      assert.equal(result.status,'APPLY_FAILED'); assert.equal(result.errorCode,'ACTIVATION_CONFLICT');
      assert.equal(result.createdChildDocuments,15); await absentActivation();
    });
  } finally {await db.terminate(); await deleteApp(app);}
});
