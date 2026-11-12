"use strict";
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const { confirm } = require("./schedule-service");
initializeApp();
exports.confirmSchedule = onCall({ region: "asia-northeast3", maxInstances: 2 },
  (request) => confirm(getFirestore(), request.auth?.uid, request.data));
