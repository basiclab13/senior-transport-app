'use strict';
const {getFirestore}=require('firebase-admin/firestore');
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {defineSecret,defineString}=require('firebase-functions/params');
const {productionSuggest}=require('./production-ai-service');
const {generateGemini}=require('./gemini-schedule');
const key=defineSecret('GEMINI_API_KEY');
const model=defineString('GEMINI_MODEL',{default:'gemini-3.8-flash'});
exports.suggestSchedule=onCall({region:'asia-northeast3',maxInstances:1,minInstances:0,concurrency:1,
  timeoutSeconds:90,enforceAppCheck:false,secrets:[key]},async request=>{
  const db=getFirestore();
  if(process.env.FUNCTIONS_EMULATOR==='true'||db.projectId!=='senior-transport-app'||
    process.env.GCLOUD_PROJECT!=='senior-transport-app'||process.env.FIRESTORE_EMULATOR_HOST||process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new HttpsError('failed-precondition','운영 AI 연결 설정을 확인해 주세요.');
  }
  return productionSuggest(db,request.auth?.uid,request.data,{app:request.app,
    generate:input=>generateGemini(input,{apiKey:key.value(),model:model.value()}),
    log:record=>console.info(JSON.stringify(record))});
});
