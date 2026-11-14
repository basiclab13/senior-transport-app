'use strict';
const {HttpsError}=require('firebase-functions/v2/https');
const {validateRequest,safeViolation}=require('./validation');
const {suggestCore}=require('./suggestion-service');
const {anonymize}=require('./ai-privacy');
const {authorize,reserve,claim,finish}=require('./ai-request-policy');
const {randomUUID}=require('node:crypto');
const {previewRequest}=require('./catalog-preview-context');

async function productionSuggest(db,uid,input,{generate,app,clock=Date.now,log=()=>{}}={}) {
  const diagnosticId=randomUUID(),started=clock();
  let stage='authorize',ticket;
  const emit=(event,error)=>{
    try{log({component:'production-suggestSchedule',diagnosticId,event,stage,elapsedMs:Math.max(0,clock()-started),
      ...(error?{code:error instanceof HttpsError?error.code:'internal',violation:safeViolation(error)||'UNCLASSIFIED'}:{})});}catch{}
  };
  try {
    if(!uid)throw new HttpsError('unauthenticated','로그인이 필요합니다.');
    const request=previewRequest(input);
    validateRequest(request.schedule);
    await authorize(db,uid,input,app);
    emit('started');
    const result=await suggestCore(db,uid,request.schedule,{
      ...(request.contextReader?{contextReader:request.contextReader}:{}),
      onStage:value=>{stage=value;},
      generate:async data=>{
        const privateInput=anonymize(data);
        if(Buffer.byteLength(JSON.stringify(privateInput.input))>64000)throw new HttpsError('invalid-argument','AI 테스트 데이터가 너무 큽니다. 코스와 이용자 수를 확인해 주세요.');
        ticket=await reserve(db,uid,input,app,clock());
        if(!ticket.policy.allowFictionalLocations)delete privateInput.input.locationModel;
        await claim(db,ticket,clock());
        stage='gemini-generate';emit('calling');
        return privateInput.restore(await generate(privateInput.input));
      },
    });
    stage='finalize';
    await authorize(db,uid,input,app); // Revoke test mode/admin approval while the call is running.
    if(!ticket||!await finish(db,ticket,true,clock()))throw new HttpsError('aborted','AI 요청이 만료되었습니다. 새 요청을 시작해 주세요.');
    emit('completed');return request.contextReader?{...result,previewContext:input.previewContext}:result;
  } catch(error) {
    if(ticket)try{await finish(db,ticket,false,clock());}catch{} // Tombstone survives uncertain acknowledgement.
    emit('failed',error);
    if(error instanceof HttpsError)throw error;
    throw new HttpsError('unavailable','AI 요청을 완료하지 못했습니다. 기존 일정은 유지됩니다.');
  }
}
module.exports={productionSuggest};
