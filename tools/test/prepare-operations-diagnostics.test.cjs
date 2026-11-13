'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const {resolve}=require('node:path');
const {guard,preparationDiagnostic}=require('../prepare_operations_emulator.cjs');
const valid={GCLOUD_PROJECT:'demo-senior-transport',FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099'};

test('each environment guard reports a distinct cause and still rejects production / remote hosts',()=>{
  for(const [change,code] of [
    [{GCLOUD_PROJECT:'senior-transport-app'},'PROJECT_MISMATCH'],
    [{FIRESTORE_EMULATOR_HOST:'remote:8080'},'FIRESTORE_HOST_INVALID'],
    [{FIREBASE_AUTH_EMULATOR_HOST:''},'AUTH_HOST_INVALID'],
  ])assert.throws(()=>guard({...valid,...change}),e=>e.code===code);
  assert.doesNotThrow(()=>guard(valid));
});
test('CLI failures distinguish missing environment and password before any SDK / data access',()=>{
  for(const [change,code,stage] of [
    [{GCLOUD_PROJECT:''},'PROJECT_MISMATCH','environment'],
    [{FIRESTORE_EMULATOR_HOST:''},'FIRESTORE_HOST_INVALID','environment'],
    [{FIREBASE_AUTH_EMULATOR_HOST:''},'AUTH_HOST_INVALID','environment'],
    [{EMULATOR_USER_PASSWORD:''},'PASSWORD_REQUIRED','password'],
    [{EMULATOR_USER_PASSWORD:'private'},'PASSWORD_TOO_SHORT','password'],
  ]) {
    const result=spawnSync(process.execPath,[resolve(__dirname,'../prepare_operations_emulator.cjs')],{
      env:{...process.env,...valid,EMULATOR_USER_PASSWORD:'',...change},encoding:'utf8',timeout:5000,
    });
    assert.equal(result.status,1);
    assert.equal(result.stdout,'');
    const diagnostic=JSON.parse(result.stderr.trim());
    assert.equal(diagnostic.errorCode,code);assert.equal(diagnostic.stage,stage);
    assert.equal(diagnostic.createdAccounts,0);assert.equal(diagnostic.createdSchedules,0);
    assert.ok(!result.stderr.includes('private'));
  }
});
test('catalog/account conflicts retain their specific cause and safe progress only',()=>{
  for(const code of ['EXISTING_SETTINGS_CONFLICT','CATALOG_METADATA_CONFLICT','CATALOG_COUNT_CONFLICT',
    'CATALOG_CONTENT_CONFLICT','ACCOUNT_DISABLED','PROFILE_CONFLICT']) {
    const diagnostic=preparationDiagnostic({code,message:'do-not-print-secret'},
      {stage:'catalog-verify',createdAccounts:2,createdSchedules:0,password:'do-not-print-secret'});
    assert.equal(diagnostic.errorCode,code);assert.equal(diagnostic.createdAccounts,2);
    assert.ok(!JSON.stringify(diagnostic).includes('do-not-print-secret'));
  }
});
test('service errors report allowlisted codes without messages, stack, identities or credentials',()=>{
  const marker='do-not-print-secret';
  for(const code of [14,'ECONNREFUSED','auth/internal-error','auth/invalid-password','MODULE_NOT_FOUND',marker]) {
    const diagnostic=preparationDiagnostic({code,message:marker,stack:marker,details:{password:marker}},
      {stage:'auth-create',createdAccounts:0,createdSchedules:0});
    assert.ok(!JSON.stringify(diagnostic).includes(marker));
    if(code===marker)assert.equal(diagnostic.serviceCode,undefined);
    else assert.equal(diagnostic.serviceCode,code);
  }
  assert.equal(preparationDiagnostic({code:14},{stage:'catalog-read'}).errorCode,'EMULATOR_UNAVAILABLE');
  assert.equal(preparationDiagnostic({code:'MODULE_NOT_FOUND'},{stage:'sdk-initialization'}).errorCode,'DEPENDENCIES_MISSING');
  assert.equal(preparationDiagnostic({code:'auth/internal-error'},{stage:'auth-create'}).errorCode,'AUTH_REQUEST_FAILED');
});
