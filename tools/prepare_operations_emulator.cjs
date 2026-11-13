'use strict';
const {createRequire} = require('node:module');
const {resolve} = require('node:path');
const {isDeepStrictEqual} = require('node:util');
const {randomUUID} = require('node:crypto');
const {operationsCatalog,operationRequest} = require('./operations_fixture.cjs');
const {registerCatalog} = require('./fictional_catalog.cjs');

const guidance={
  PROJECT_MISMATCH:'이 터미널의 GCLOUD_PROJECT를 demo-senior-transport로 설정하세요. Firebase CLI 기본 프로젝트는 사용하지 않습니다.',
  FIRESTORE_HOST_INVALID:'이 터미널의 FIRESTORE_EMULATOR_HOST를 loopback 호스트:포트로 설정하세요(기본 127.0.0.1:8080).',
  AUTH_HOST_INVALID:'이 터미널의 FIREBASE_AUTH_EMULATOR_HOST를 loopback 호스트:포트로 설정하세요(기본 127.0.0.1:9099).',
  PASSWORD_REQUIRED:'같은 터미널에 EMULATOR_USER_PASSWORD를 설정하세요. node 도구는 Functions의 .env.local이나 .secret.local을 자동으로 읽지 않습니다.',
  PASSWORD_TOO_SHORT:'EMULATOR_USER_PASSWORD는 12자 이상이어야 합니다. 기존 계정을 재사용할 때는 처음 설정한 비밀번호를 사용하세요.',
  EXISTING_SETTINGS_CONFLICT:'기존 settings/schedules가 다른 fixture를 가리킵니다. 기존 데이터를 삭제하거나 덮어쓰지 말고 연결 대상과 등록 상태를 확인하세요.',
  CATALOG_METADATA_CONFLICT:'기존 operations-20x80-v1 부모 문서 또는 settings/schedules가 예상 fixture와 다릅니다. 기존 데이터는 보존하고 확인하세요.',
  CATALOG_COUNT_CONFLICT:'기존 catalog 하위 컬렉션의 문서 수가 다릅니다. 기존 데이터를 보존하고 부분 등록 여부를 확인하세요.',
  CATALOG_CONTENT_CONFLICT:'기존 catalog 하위 문서가 예상 fixture와 다릅니다. 기존 데이터를 보존하고 변경 내용을 확인하세요.',
  ACCOUNT_DISABLED:'기존 가상 Authentication 계정이 비활성 상태입니다. 계정을 임의로 변경하지 말고 설정을 확인하세요.',
  PROFILE_CONFLICT:'기존 users 문서가 예상 가상 계정 프로필과 다릅니다. 사용자 문서를 덮어쓰지 않고 중단했습니다.',
};
function fail(code) {const error=new Error('Fixture preparation rejected');error.code=code;throw error;}
function preparationDiagnostic(error,progress={}) {
  const known=Object.hasOwn(guidance,error?.code)?error.code:null;
  const allowedCodes=new Set(['ECONNREFUSED','ECONNRESET','ETIMEDOUT','ENOTFOUND','MODULE_NOT_FOUND',
    'auth/internal-error','auth/invalid-password','auth/invalid-email','auth/email-already-exists',
    'auth/insufficient-permission','auth/project-not-found','permission-denied','failed-precondition','invalid-argument','aborted','unavailable']);
  const serviceCode=allowedCodes.has(error?.code)?error.code:
    (Number.isInteger(error?.code)&&error.code>=0&&error.code<=16?error.code:undefined);
  const stages=['environment','password','sdk-initialization','catalog-read','catalog-register','catalog-verify',
    'auth-find','auth-create','profile-read','profile-create','schedule-read','schedule-confirm','cleanup'];
  const stage=stages.includes(progress.stage)?progress.stage:'unknown';
  return {errorCode:known||(serviceCode==='MODULE_NOT_FOUND'?'DEPENDENCIES_MISSING':
    stage.startsWith('auth-')?'AUTH_REQUEST_FAILED':serviceCode===14||['ECONNREFUSED','ECONNRESET','ETIMEDOUT','ENOTFOUND','unavailable'].includes(serviceCode)?'EMULATOR_UNAVAILABLE':'PREPARATION_FAILED'),
    stage,...(serviceCode!==undefined?{serviceCode}:{}),
    createdAccounts:progress.createdAccounts||0,createdSchedules:progress.createdSchedules||0,
    guidance:known?guidance[known]:serviceCode==='MODULE_NOT_FOUND'?'functions 폴더에서 npm ci로 기존 의존성을 설치한 뒤 다시 실행하세요.':
      '실패 단계의 Emulator 연결·로그·기존 fixture를 확인하세요. 앞 단계의 일부 데이터가 생성되었을 수 있으므로 삭제하거나 비밀번호를 바꾸지 마세요.',
  };
}

function guard(env=process.env) {
  if (env.GCLOUD_PROJECT!=='demo-senior-transport') fail('PROJECT_MISMATCH');
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(env.FIRESTORE_EMULATOR_HOST||'')) fail('FIRESTORE_HOST_INVALID');
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(env.FIREBASE_AUTH_EMULATOR_HOST||'')) fail('AUTH_HOST_INVALID');
}

async function prepare(password) {
  const progress={stage:'environment',createdAccounts:0,createdSchedules:0};
  try {return await prepareFixture(password,progress);} catch(error) {
    const safe=new Error('Local fixture preparation failed; no credentials are printed.');
    safe.diagnostic=preparationDiagnostic(error,progress);
    throw safe;
  }
}
async function prepareFixture(password,progress) {
  guard();
  progress.stage='password';
  if (typeof password!=='string'||password.length===0) fail('PASSWORD_REQUIRED');
  if (password.length<12) fail('PASSWORD_TOO_SHORT');
  progress.stage='sdk-initialization';
  const requireFunctions=createRequire(resolve(__dirname,'../functions/package.json'));
  const {initializeApp,deleteApp}=requireFunctions('firebase-admin/app');
  const {getAuth}=requireFunctions('firebase-admin/auth');
  const {getFirestore}=requireFunctions('firebase-admin/firestore');
  const {confirm}=require('../functions/schedule-service');
  const app=initializeApp({projectId:process.env.GCLOUD_PROJECT},`operations-${randomUUID()}`);
  const db=getFirestore(app); const auth=getAuth(app);
  const catalog=operationsCatalog(); const version='operations-20x80-v1';
  const accounts=[];
  let createdAccounts=0,createdSchedules=0;
  let primaryError;
  try {
    progress.stage='catalog-read';
    const parent=await db.doc(`catalogs/${version}`).get();
    if (!parent.exists) {
      const settings=await db.doc('settings/schedules').get();
      if (settings.exists) fail('EXISTING_SETTINGS_CONFLICT');
      progress.stage='catalog-register';
      await registerCatalog(db,version,catalog);
    } else {
      progress.stage='catalog-verify';
      if (!isDeepStrictEqual(parent.data(),{ready:true,fictional:true,schemaVersion:1}) ||
          (await db.doc('settings/schedules').get()).data()?.catalogVersion!==version) fail('CATALOG_METADATA_CONFLICT');
      for (const [collection,items] of Object.entries(catalog)) {
        const docs=await db.collection(`catalogs/${version}/${collection}`).get();
        if (docs.size!==items.length) fail('CATALOG_COUNT_CONFLICT');
        for (const {id,...data} of items) if (!isDeepStrictEqual(docs.docs.find((d)=>d.id===id)?.data(),data)) fail('CATALOG_CONTENT_CONFLICT');
      }
    }
    for (const entry of [{role:'admin'},...catalog.staff.map((s)=>({role:'staff',staffId:s.id}))]) {
      const email=`ops-${entry.staffId||'admin'}@example.invalid`;
      let user;
      progress.stage='auth-find';
      try {user=await auth.getUserByEmail(email);} catch(error) {
        if (error.code!=='auth/user-not-found') throw error;
        progress.stage='auth-create';
        user=await auth.createUser({email,password}); createdAccounts++;progress.createdAccounts=createdAccounts;
      }
      progress.stage='profile-read';
      const ref=db.doc(`users/${user.uid}`); const profile=await ref.get();
      const expected={active:true,...entry};
      if (user.disabled) fail('ACCOUNT_DISABLED');
      if (profile.exists&&!isDeepStrictEqual(profile.data(),expected)) fail('PROFILE_CONFLICT');
      if (!profile.exists) {progress.stage='profile-create';await ref.create(expected);}
      accounts.push({email,uid:user.uid,...entry});
    }
    const admin=accounts.find((a)=>a.role==='admin');
    const wall=new Date(Date.now()+9*3600000);
    const today=wall.toISOString().slice(0,10);
    const tomorrow=new Date(Date.UTC(wall.getUTCFullYear(),wall.getUTCMonth(),wall.getUTCDate()+1)).toISOString().slice(0,10);
    for (const date of [today,tomorrow]) for (const period of ['morning','afternoon']) {
      progress.stage='schedule-read';
      if (!(await db.doc(`schedules/${date}_${period}`).get()).exists) {
        progress.stage='schedule-confirm';
        await confirm(db,admin.uid,operationRequest(catalog,date,period,version,randomUUID())); createdSchedules++;progress.createdSchedules=createdSchedules;
      }
    }
    return {projectId:process.env.GCLOUD_PROJECT,version,today,tomorrow,createdAccounts,createdSchedules,
      counts:{staff:catalog.staff.length,vehicles:catalog.vehicles.length,passengers:catalog.passengers.length,baseRoutes:catalog.baseRoutes.length},accounts};
  } catch(error) {primaryError=error;throw error;}
  finally {
    try {try {await db.terminate();} finally {await deleteApp(app);}}
    catch(error) {if(!primaryError){progress.stage='cleanup';throw error;}}
  }
}

if (require.main===module) {
  prepare(process.env.EMULATOR_USER_PASSWORD).then(({accounts,...summary})=>console.log(JSON.stringify({...summary,accounts:accounts.length},null,2)))
    .catch(error=>{console.error(JSON.stringify({status:'FAILED',...error.diagnostic}));process.exitCode=1;});
}
module.exports={prepare,guard,preparationDiagnostic};
