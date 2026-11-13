"use strict";
// Loaded only in the demo Functions Emulator; never during production discovery.
const { getFirestore } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { randomUUID } = require('node:crypto');
const { defineSecret, defineString } = require('firebase-functions/params');
const { suggest, guardSuggestionEnvironment } = require('./suggestion-service');
const { generateGemini } = require('./gemini-schedule');
const { safeViolation } = require('./validation');
const geminiKey = defineSecret('GEMINI_API_KEY');
const geminiModel = defineString('GEMINI_MODEL', {default:'gemini-3.8-flash'});
exports.suggestSchedule = onCall({region:'asia-northeast3',maxInstances:1,timeoutSeconds:90,secrets:[geminiKey]},
  async request => {
    const diagnosticId=randomUUID(),started=performance.now();
    let stage='environment';
    const emit=(event,extra={})=>console.info(JSON.stringify({component:'suggestSchedule',diagnosticId,event,stage,
      elapsedMs:Math.round(performance.now()-started),...extra}));
    emit('started');
    try {
      guardSuggestionEnvironment(getFirestore());
      const result=await suggest(getFirestore(),request.auth?.uid,request.data,{
        onStage:value=>{stage=value;emit('stage');},
        onValidationFailure:summary=>emit('validation-failed',summary),
        generate: input => generateGemini(input,{apiKey:geminiKey.value(),model:geminiModel.value(),diagnosticId}),
      });
      emit('completed');
      return result;
    } catch(error) {
      emit('failed',{errorType:'CALLABLE_ERROR',callableCode:error instanceof HttpsError?error.code:'internal',
        ...(safeViolation(error)?{violationType:safeViolation(error)}:{})});
      throw error;
    }
  });
