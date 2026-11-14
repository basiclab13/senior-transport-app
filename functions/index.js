"use strict";
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { onCall } = require('firebase-functions/v2/https');
const { confirm } = require('./schedule-service');
const { setStaffAbsence } = require('./staff-absence-service');
initializeApp();
exports.registerWorkPhoto = require('./work-photos').registerWorkPhoto;
exports.getWorkPhotos = require('./work-photos').getWorkPhotos;
exports.confirmSchedule = onCall({ region: 'asia-northeast3', maxInstances: 2 },
  (request) => confirm(getFirestore(), request.auth?.uid, request.data));
exports.setStaffAbsence = onCall({ region: 'asia-northeast3', maxInstances: 2 },
  (request) => setStaffAbsence(getFirestore(), request.auth?.uid, request.data));
// Keep AI parameters/Secrets out of production discovery, not merely invocation.
// The AI handler additionally verifies loopback Emulator hosts on every request.
if (process.env.FUNCTIONS_EMULATOR === 'true' &&
    process.env.GCLOUD_PROJECT === 'demo-senior-transport') {
  exports.suggestSchedule = require('./emulator-ai').suggestSchedule;
} else if (process.env.FUNCTIONS_EMULATOR !== 'true' &&
    process.env.GCLOUD_PROJECT === 'senior-transport-app') {
  exports.suggestSchedule = require('./production-ai').suggestSchedule;
}
