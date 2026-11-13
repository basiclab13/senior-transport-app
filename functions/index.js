"use strict";
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { randomUUID } = require('node:crypto');
const { confirm } = require("./schedule-service");
const { setStaffAbsence } = require("./staff-absence-service");
const { defineSecret, defineString } = require('firebase-functions/params');
const { suggest, guardSuggestionEnvironment } = require('./suggestion-service');
const { generateGemini } = require('./gemini-schedule');
const { safeViolation } = require('./validation');
const geminiKey = defineSecret('GEMINI_API_KEY');
const geminiModel = defineString('GEMINI_MODEL', {default:'gemini-3.8-flash'});
initializeApp();
exports.confirmSchedule = onCall({ region: "asia-northeast3", maxInstances: 2 },
  (request) => confirm(getFirestore(), request.auth?.uid, request.data));
exports.setStaffAbsence = onCall({ region: "asia-northeast3", maxInstances: 2 },
  (request) => setStaffAbsence(getFirestore(), request.auth?.uid, request.data));
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
