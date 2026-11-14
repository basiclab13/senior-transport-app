'use strict';
// Operator ADC only. Default is read-only. No scheduled deletion is exported.
const {initializeApp,deleteApp}=require('../functions/node_modules/firebase-admin/app');
const {getFirestore}=require('../functions/node_modules/firebase-admin/firestore');
const {getStorage}=require('../functions/node_modules/firebase-admin/storage');
const {cleanupWorkPhotos}=require('../functions/work-photo-service');
async function main(){
  const args=process.argv.slice(2),allowed=new Set(['--project','--bucket','--confirm-project','--apply','--approve-delete-work-photos']);
  const values={};
  for(let i=0;i<args.length;i++){
    const key=args[i];if(!allowed.has(key)||Object.hasOwn(values,key))throw Error('INVALID_OPTIONS');
    values[key]=['--apply','--approve-delete-work-photos'].includes(key)?true:args[++i];
  }
  const projectId=values['--project'],bucket=values['--bucket'],apply=values['--apply']===true;
  if(typeof projectId!=='string'||!(/^(demo-[a-z0-9-]+)$/.test(projectId)||projectId==='senior-transport-app')||
    typeof bucket!=='string'||!/^[a-z0-9][a-z0-9._-]{2,221}$/.test(bucket))throw Error('EXPLICIT_PROJECT_AND_BUCKET_REQUIRED');
  if(apply&&(values['--confirm-project']!==projectId||values['--approve-delete-work-photos']!==true))throw Error('DELETE_APPROVAL_REQUIRED');
  const hosts=['FIRESTORE_EMULATOR_HOST','FIREBASE_STORAGE_EMULATOR_HOST'];
  if(projectId.startsWith('demo-')?!hosts.every(k=>/^(127\.0\.0\.1|localhost):\d+$/.test(process.env[k]||'')):
    ['FUNCTIONS_EMULATOR','FIRESTORE_EMULATOR_HOST','FIREBASE_STORAGE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST'].some(k=>process.env[k]))throw Error('ENVIRONMENT_MISMATCH');
  const app=initializeApp({projectId});
  try{console.log(JSON.stringify({status:'VERIFIED',dryRun:!apply,...await cleanupWorkPhotos(getFirestore(app),getStorage(app).bucket(bucket),{apply})}));}
  finally{await deleteApp(app);}
}
if(require.main===module)main().catch(()=>{console.error(JSON.stringify({status:'REJECTED',guidance:'명시적 프로젝트·버킷·정리 승인과 서버 기록을 확인하세요. 오류 원문은 출력하지 않습니다.'}));process.exitCode=1;});
