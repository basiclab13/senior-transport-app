'use strict';
const {getFirestore}=require('firebase-admin/firestore');
const {getStorage}=require('firebase-admin/storage');
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {defineString}=require('firebase-functions/params');
const service=require('./work-photo-service');
const bucketName=defineString('WORK_PHOTO_BUCKET',{default:''});
function handler(name){return onCall({region:'asia-northeast3',maxInstances:1,minInstances:0,concurrency:1,timeoutSeconds:60,enforceAppCheck:false,
  ...(process.env.FUNCTIONS_EMULATOR==='true'?{}:{serviceAccount:'work-photos@senior-transport-app.iam.gserviceaccount.com'})},async request=>{
  const db=getFirestore(),emulator=process.env.FUNCTIONS_EMULATOR==='true';
  let bucket;
  try{
    if(emulator){
      if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||db.projectId!=='demo-senior-transport'||
        !['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','FIREBASE_STORAGE_EMULATOR_HOST'].every(k=>/^(127\.0\.0\.1|localhost):\d+$/.test(process.env[k]||'')))throw new HttpsError('failed-precondition','사진 Emulator 연결을 확인해 주세요.');
      bucket=`${db.projectId}.firebasestorage.app`;
    }else{
      if(db.projectId!=='senior-transport-app'||process.env.GCLOUD_PROJECT!=='senior-transport-app'||
        process.env.FIRESTORE_EMULATOR_HOST||process.env.FIREBASE_AUTH_EMULATOR_HOST||process.env.FIREBASE_STORAGE_EMULATOR_HOST)throw new HttpsError('failed-precondition','사진 서버 연결을 확인해 주세요.');
      bucket=bucketName.value();
      if(!/^[a-z0-9][a-z0-9._-]{2,221}$/.test(bucket))throw new HttpsError('failed-precondition','사진 전용 버킷 설정을 확인해 주세요.');
    }
    return await service[name](db,getStorage().bucket(bucket),request.auth?.uid,request.data,{app:request.app});
  }catch(error){
    console.info(JSON.stringify({component:name,event:'failed',code:error instanceof HttpsError?error.code:'unavailable'}));
    if(error instanceof HttpsError)throw error;
    throw new HttpsError('unavailable','사진 기록을 확인하지 못했습니다. 연결을 확인하고 기록을 새로고침해 주세요.');
  }
});}
exports.registerWorkPhoto=handler('registerWorkPhoto');
exports.getWorkPhotos=handler('getWorkPhotos');
