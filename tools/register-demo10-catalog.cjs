'use strict';
const {readFileSync}=require('node:fs');
const {resolve}=require('node:path');
const {createRequire}=require('node:module');
const {guard}=require('./ai25_registration.cjs');
const {VERSION,PREVIOUS,makePlan}=require('./demo10_fixture.cjs');
const {register,transition}=require('./demo10_registration.cjs');
function parse(args,env=process.env){
  const o={action:args[0],apply:false},seen=new Set();
  if(!['register','switch','rollback'].includes(o.action))throw Error('ACTION_REQUIRED');
  for(let i=1;i<args.length;i++){
    const k=args[i];if(seen.has(k))throw Error('DUPLICATE_OPTION');seen.add(k);
    if(['--project','--confirm-project','--approve-catalog'].includes(k)){
      const v=args[++i];if(!v||v.startsWith('--'))throw Error('MISSING_VALUE');
      o[k==='--project'?'project':k==='--confirm-project'?'confirmation':'approval']=v;
    }else if(['--apply','--dry-run','--verify','--plan'].includes(k))o[k.slice(2).replace('dry-run','dryRun')]=true;
    else throw Error('UNKNOWN_OPTION');
  }
  if([o.apply,o.dryRun,o.verify,o.plan].filter(Boolean).length>1)throw Error('CONFLICTING_MODES');
  if(o.verify&&o.action!=='register'||o.plan&&o.action!=='register')throw Error('INVALID_MODE');
  guard(o.project,env);
  const target=o.action==='rollback'?PREVIOUS:VERSION;
  if(o.apply&&(o.confirmation!==o.project||o.approval!==target))throw Error('APPROVAL_REQUIRED');
  if(!o.apply&&(o.confirmation||o.approval))throw Error('UNEXPECTED_APPROVAL');
  return {...o,rollback:o.action==='rollback'};
}
async function main(args=process.argv.slice(2)){
  let app,o;
  try{
    o=parse(args);
    const manifest=JSON.parse(readFileSync(resolve(__dirname,'../docs/fixtures/demo-10x24-v1.baseline.json'),'utf8'));
    const plan=makePlan(manifest);
    if(o.plan){console.log(JSON.stringify({status:'OFFLINE_PLAN',...plan,firebaseAccess:false},null,2));return;}
    const requireSdk=createRequire(resolve(__dirname,'../functions/package.json'));
    const sdk=requireSdk('firebase-admin/app');
    app=sdk.initializeApp({projectId:o.project,...(o.project.startsWith('demo-')?{}:{credential:sdk.applicationDefault()})},'demo10-operator');
    const db=requireSdk('firebase-admin/firestore').getFirestore(app);
    const result=await(o.action==='register'?register(db,manifest,o):transition(db,manifest,o));
    console.log(JSON.stringify(result,null,2));
    if(!['APPLIED','VERIFIED','DRY_RUN_OK','SWITCHED'].includes(result.status))process.exitCode=2;
  }catch(error){
    console.error(JSON.stringify({status:'STOPPED',writesRequested:o?.apply===true,
      errorCode:/^[A-Z][A-Z0-9_]{2,70}$/.test(error.message||'')?error.message:'READ_OR_COMMIT_FAILED',
      guidance:'Check explicit project/catalog approvals, ADC/IAM, expected pointer, catalog integrity and active staff mappings. If a write outcome is uncertain, run register --verify or a read-only switch/rollback check first; do not automatically retry, delete or overwrite.'}));
    process.exitCode=2;
  }finally{if(app)await app.delete();}
}
if(require.main===module)main();
module.exports={parse};
