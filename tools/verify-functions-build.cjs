'use strict';
// Offline SDK discovery only. Does not run handlers, load env files or call Firebase.
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');

function inspectEntry(emulator = false, project = 'senior-transport-app') {
  const env = {...process.env, GCLOUD_PROJECT: project,
    FIREBASE_CONFIG: JSON.stringify({projectId: project})};
  for (const key of Object.keys(env)) {
    if (/EMULATOR|GEMINI|GOOGLE_APPLICATION_CREDENTIALS|FUNCTIONS_MANIFEST_OUTPUT_PATH/.test(key)) delete env[key];
  }
  if (emulator) env.FUNCTIONS_EMULATOR = 'true';
  const probe = `
    const path = require('node:path');
    const {loadStack} = require(path.resolve('node_modules/firebase-functions/lib/runtime/loader.js'));
    loadStack(process.cwd()).then(stack => {
      const aiLoaded = Object.keys(require.cache).some(p => /[\\\\/](emulator-ai|gemini-schedule|suggestion-service)\\.js$/.test(p));
      console.log(JSON.stringify({endpoints: stack.endpoints, params: stack.params || [],
        requiredAPIs: stack.requiredAPIs || [], aiLoaded}));
    }).catch(() => {process.exitCode = 1;});
  `;
  const result = spawnSync(process.execPath, ['-e', probe], {
    cwd: path.join(root, 'functions'), env, encoding: 'utf8', timeout: 15000,
  });
  // Never echo child diagnostics or environment values.
  if (result.status !== 0) throw new Error('FUNCTION_DISCOVERY_FAILED');
  try { return JSON.parse(result.stdout.trim()); }
  catch { throw new Error('FUNCTION_MANIFEST_INVALID'); }
}

function verify() {
  if (process.env.FUNCTIONS_EMULATOR || process.env.FIREBASE_EMULATOR_HUB ||
      process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST ||
      (process.env.GCLOUD_PROJECT && process.env.GCLOUD_PROJECT !== 'senior-transport-app')) {
    throw new Error('USE_CLEAN_PRODUCTION_SHELL');
  }
  const config = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json'), 'utf8').replace(/^\uFEFF/, ''));
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'functions/package.json'), 'utf8'));
  assert.equal(config.functions.source, 'functions');
  assert.equal(config.functions.runtime, 'nodejs22');
  assert.equal(pkg.engines.node, '22');
  assert.equal(pkg.main, 'index.js');
  assert.ok(config.functions.ignore.includes('.secret.local'));
  assert.ok(config.functions.ignore.includes('.env.local'));
  const manifest = inspectEntry();
  const names = Object.keys(manifest.endpoints).sort();
  assert.deepEqual(names, ['confirmSchedule', 'getWorkPhotos', 'registerWorkPhoto', 'setStaffAbsence', 'suggestSchedule']);
  assert.deepEqual(manifest.params.map(p=>[p.name,p.type]).sort(), [['GEMINI_API_KEY','secret'],['GEMINI_MODEL','string'],['WORK_PHOTO_BUCKET','string']]);
  for(const name of ['registerWorkPhoto','getWorkPhotos']) {
    const endpoint=manifest.endpoints[name];
    assert.equal(endpoint.platform,'gcfv2');assert.deepEqual(endpoint.region,['asia-northeast3']);
    assert.equal(endpoint.maxInstances,1);assert.equal(endpoint.concurrency,1);assert.equal(endpoint.timeoutSeconds,60);
    assert.equal((endpoint.secretEnvironmentVariables||[]).length,0);
    assert.equal(endpoint.serviceAccountEmail,'work-photos@senior-transport-app.iam.gserviceaccount.com');
  }
  for (const name of ['confirmSchedule','setStaffAbsence']) {
    const endpoint=manifest.endpoints[name];
    assert.equal(endpoint.platform, 'gcfv2');
    assert.deepEqual(endpoint.region, ['asia-northeast3']);
    assert.equal(endpoint.maxInstances, 2);
    assert.ok(endpoint.callableTrigger);
    assert.equal((endpoint.secretEnvironmentVariables || []).length, 0);
  }
  const ai=manifest.endpoints.suggestSchedule;
  assert.equal(ai.platform,'gcfv2');
  assert.deepEqual(ai.region,['asia-northeast3']);
  assert.equal(ai.maxInstances,1);assert.equal(ai.minInstances,0);assert.equal(ai.concurrency,1);
  assert.equal(ai.timeoutSeconds,90);
  assert.deepEqual(ai.secretEnvironmentVariables,[{key:'GEMINI_API_KEY'}]);
  assert.notEqual(ai.callableTrigger.enforceAppCheck,true);
  return {status: 'VERIFIED', projectId: 'senior-transport-app', runtime: 'nodejs22',
    region: 'asia-northeast3', endpoints: names, parameters: 3, secretBindings: 1,
    aiDefaultMode: 'off', scheduleFunctionSecretBindings: 0, remoteRequests: 0};
}

if (require.main === module) {
  try { console.log(JSON.stringify(verify())); }
  catch (error) {
    console.error(JSON.stringify({status: 'REJECTED', errorCode:
      ['USE_CLEAN_PRODUCTION_SHELL', 'FUNCTION_DISCOVERY_FAILED', 'FUNCTION_MANIFEST_INVALID'].includes(error.message)
        ? error.message : 'FUNCTION_DEPLOYMENT_CONTRACT_MISMATCH'}));
    process.exitCode = 1;
  }
}
module.exports = {inspectEntry, verify};
