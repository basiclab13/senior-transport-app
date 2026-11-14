'use strict';
// Operator tool. Fixed catalog scope; no settings/account/schedule activation.
const {readFileSync}=require('node:fs');
const {resolve}=require('node:path');
const {createRequire}=require('node:module');
const {makePlan,VERSION}=require('./ai25_fixture.cjs');
const {guard,registerAi25,PROJECT}=require('./ai25_registration.cjs');
function parse(args,env=process.env){
  const result={apply:false},seen=new Set();
  for(let i=0;i<args.length;i++){
    const key=args[i];if(seen.has(key))throw new Error('DUPLICATE_OPTION');seen.add(key);
    if(['--project','--confirm-project','--approve-catalog'].includes(key)){
      const value=args[++i];if(!value||value.startsWith('--'))throw new Error('MISSING_VALUE');
      result[key==='--project'?'project':key==='--confirm-project'?'confirmation':'approval']=value;
    }else if(key==='--apply')result.apply=true;
    else if(key==='--dry-run')result.dryRun=true;
    else if(key==='--plan')result.plan=true;
    else if(key==='--verify')result.verify=true;
    else throw new Error('UNKNOWN_OPTION');
  }
  if([result.apply,result.dryRun,result.plan,result.verify].filter(Boolean).length>1)throw new Error('CONFLICTING_MODES');
  if(result.apply&&result.confirmation!==result.project)throw new Error('PROJECT_CONFIRMATION_REQUIRED');
  if(!result.apply&&result.confirmation)throw new Error('UNEXPECTED_CONFIRMATION');
  if(!result.apply&&result.approval)throw new Error('UNEXPECTED_APPROVAL');
  if(result.project&&result.project!==PROJECT&&!/^demo-[a-z0-9-]+$/.test(result.project))throw new Error('PROJECT_NOT_ALLOWED');
  if(!result.project){if(result.apply||result.dryRun||result.verify)throw new Error('PROJECT_ID_REQUIRED');result.plan=true;}
  if(result.approval!==undefined&&result.approval!==VERSION)throw new Error('CATALOG_APPROVAL_MISMATCH');
  if(result.project===PROJECT&&result.apply&&result.approval!==VERSION)throw new Error('CATALOG_APPROVAL_REQUIRED');
  if(!result.plan)guard(result.project,env);
  return result;
}
async function main(args=process.argv.slice(2)){
  let app,admin;
  try{
    const options=parse(args),manifest=JSON.parse(readFileSync(resolve(__dirname,'../docs/fixtures/ai-test-25x80-v1.baseline.json'),'utf8'));
    const plan=makePlan(manifest);
    if(options.plan){console.log(JSON.stringify({status:'OFFLINE_PLAN',projectId:options.project??null,databaseId:'(default)',catalogVersion:plan.catalogVersion,counts:plan.counts,
      childDocuments:plan.documents.length,metadataDocuments:1,manifestSha256:plan.manifestSha256,firebaseAccess:false,writes:false,settingsWrites:0}));return 0;}
    const dependencies=createRequire(resolve(__dirname,'../functions/package.json'));
    admin=dependencies('firebase-admin/app');app=admin.initializeApp({projectId:options.project,
      ...(options.project===PROJECT?{credential:admin.applicationDefault()}:{})},'ai25-fixture-operator');
    const db=dependencies('firebase-admin/firestore').getFirestore(app);
    const result=await registerAi25(db,manifest,{apply:options.apply,verify:options.verify,
      confirmation:options.confirmation,approval:options.approval});console.log(JSON.stringify({...result,projectId:options.project}));
    return ['APPLIED','DRY_RUN_OK','ALREADY_REGISTERED','VERIFIED'].includes(result.status)?0:2;
  }catch(e){
    const known=new Set(['DUPLICATE_OPTION','MISSING_VALUE','UNKNOWN_OPTION','CONFLICTING_MODES','PROJECT_CONFIRMATION_REQUIRED',
      'UNEXPECTED_CONFIRMATION','UNEXPECTED_APPROVAL','PROJECT_NOT_ALLOWED','PROJECT_ID_REQUIRED','DEMO_LOOPBACK_REQUIRED','PROJECT_MISMATCH',
      'UNEXPECTED_EMULATOR_ENVIRONMENT','DATABASE_MISMATCH','CATALOG_APPROVAL_REQUIRED','CATALOG_APPROVAL_MISMATCH','PRODUCTION_APPROVAL_REQUIRED',
      'FIXTURE_MANIFEST_MISMATCH','FIXTURE_NAMES_INVALID','FIXTURE_COUNT_INVALID','POST_WRITE_VERIFICATION_FAILED']);
    console.error(JSON.stringify({status:'REJECTED',errorCode:known.has(e.message)?e.message:'REGISTRATION_FAILED',
      guidance:'프로젝트·승인 옵션·ADC/IAM·Emulator 환경을 확인하세요. 결과가 불명확하면 --verify로 확인하며 자동 재등록·삭제·덮어쓰기·포인터 변경하지 않습니다.'}));return 2;
  }finally{if(app)try{await admin.deleteApp(app);}catch{}}
}
if(require.main===module)main().then(code=>{process.exitCode=code;});
module.exports={parse,main};
