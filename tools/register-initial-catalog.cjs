'use strict';

const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { createRequire } = require('node:module');
const { makePlan, registerInitialCatalog, EXPECTED_PROJECT } = require('./initial-catalog-registration.cjs');

const HELP = `Initial fictional catalog registration (operator-only; no deployment)
node tools/register-initial-catalog.cjs --project senior-transport-app [--dry-run]
node tools/register-initial-catalog.cjs --project senior-transport-app --plan
WRITE: add --apply --confirm-project senior-transport-app
LOCAL TEST ONLY: --emulator --project demo-... [--apply --confirm-project demo-...]
Default is read-only dry-run. --plan performs no Firebase access.
Uses docs/fixtures/deploy-test-v1.baseline.json and operator ADC/IAM.
Never updates or deletes existing documents. No --force or --scale option.`;

function parseArguments(args, env = process.env) {
  const options = { apply: false, emulator: false, offline: false };
  const seen = new Set();
  for (let i = 0; i < args.length; i++) {
    const name = args[i];
    if (seen.has(name)) throw new Error('DUPLICATE_OPTION');
    seen.add(name);
    if (['--project','--confirm-project'].includes(name)) {
      const value = args[++i];
      if (!value || value.startsWith('--')) throw new Error('MISSING_OPTION_VALUE');
      options[name === '--project' ? 'project' : 'confirmation'] = value;
    } else if (name === '--apply') options.apply = true;
    else if (name === '--dry-run') options.dryRun = true;
    else if (name === '--emulator') options.emulator = true;
    else if (name === '--plan') options.offline = true;
    else throw new Error('UNKNOWN_OPTION');
  }
  if (!options.project || (options.emulator ? !/^demo-[a-z0-9-]+$/.test(options.project) : options.project !== EXPECTED_PROJECT)) throw new Error('PROJECT_MISMATCH');
  if (options.apply && (options.dryRun || options.offline)) throw new Error('CONFLICTING_MODES');
  if (options.apply && options.confirmation !== options.project) throw new Error('PROJECT_CONFIRMATION_REQUIRED');
  if (!options.apply && options.confirmation !== undefined) throw new Error('UNEXPECTED_CONFIRMATION');
  if (!options.offline) {
    if (options.emulator) {
      const match = /^(127\.0\.0\.1|localhost):(\d{1,5})$/.exec(env.FIRESTORE_EMULATOR_HOST || '');
      if (!match || Number(match[2]) < 1 || Number(match[2]) > 65535) throw new Error('LOOPBACK_EMULATOR_REQUIRED');
    } else if (['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','FIREBASE_EMULATOR_HUB'].some((name) => env[name])) throw new Error('UNEXPECTED_EMULATOR_ENVIRONMENT');
    for (const name of ['GCLOUD_PROJECT','GOOGLE_CLOUD_PROJECT']) if (env[name] && env[name] !== options.project) throw new Error('ENVIRONMENT_PROJECT_MISMATCH');
    if (env.FIREBASE_CONFIG) {
      let configuration;
      try { configuration = JSON.parse(env.FIREBASE_CONFIG); } catch (_) { throw new Error('AMBIGUOUS_FIREBASE_CONFIG'); }
      if (configuration.projectId && configuration.projectId !== options.project) throw new Error('ENVIRONMENT_PROJECT_MISMATCH');
    }
  }
  return options;
}

async function main(args = process.argv.slice(2)) {
  if (args.length === 1 && args[0] === '--help') { console.log(HELP); return 0; }
  let options;
  let plan;
  try {
    options = parseArguments(args);
    plan = makePlan(JSON.parse(readFileSync(resolve(__dirname, '../docs/fixtures/deploy-test-v1.baseline.json'), 'utf8')));
  } catch (error) {
    console.error(JSON.stringify({status:'REJECTED', errorCode:error.code || error.message,
      guidance:'프로젝트 ID, 실행 옵션, baseline manifest를 확인하세요. Firebase에는 연결하지 않았습니다.'}));
    return 2;
  }
  if (options.offline) {
    console.log(JSON.stringify({status:'OFFLINE_PLAN', projectId:options.project, databaseId:plan.databaseId,
      catalogVersion:plan.catalogVersion, counts:plan.counts, childDocuments:plan.documents.map((doc) => doc.path),
      activationDocuments:[plan.parentPath, plan.settingsPath], manifestSha256:plan.manifestSha256,
      firebaseAccess:false, writes:false}, null, 2));
    return 0;
  }
  let app;
  let deleteApp;
  try {
    const dependencies = createRequire(resolve(__dirname, '../functions/package.json'));
    const admin = dependencies('firebase-admin/app');
    deleteApp = admin.deleteApp;
    app = admin.initializeApp({projectId:options.project,
      ...(options.emulator ? {} : {credential:admin.applicationDefault()})}, 'initial-catalog-operator');
    const db = dependencies('firebase-admin/firestore').getFirestore(app);
    const result = await registerInitialCatalog(db, plan, {apply:options.apply});
    console.log(JSON.stringify({...result, projectId:options.project}, null, 2));
    return ['APPLIED','DRY_RUN_OK','ALREADY_REGISTERED'].includes(result.status) ? 0 : 2;
  } catch (_) {
    console.error(JSON.stringify({status:'CONNECTION_FAILED', writesRequested:options.apply,
      guidance:'운영자 ADC, IAM, Firestore 연결을 확인하세요. 기존 문서의 덮어쓰기·삭제는 하지 않습니다. 인증 정보와 원본 예외는 출력하지 않습니다.'}));
    return 1;
  } finally {
    if (app && deleteApp) await deleteApp(app);
  }
}

if (require.main === module) main().then((code) => {process.exitCode=code;}).catch(() => {
  console.error(JSON.stringify({status:'FAILED', guidance:'작업을 완료하지 못했습니다. dry-run으로 상태를 확인하세요.'})); process.exitCode=1;
});
module.exports = { parseArguments, main };
