"use strict";
// Trusted developer CLI only; NOT exported as a Function and NOT shipped in app.
const host = process.env.FIRESTORE_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT;
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host || '') || !projectId?.startsWith('demo-')) {
  throw new Error('This tool only supports a loopback Firestore Emulator and a demo-* project');
}
const functionsRequire = require('node:module').createRequire(require('node:path').resolve(__dirname, '../functions/package.json'));
const { initializeApp } = functionsRequire('firebase-admin/app');
const { getFirestore } = functionsRequire('firebase-admin/firestore');
const { fictionalCatalog, registerCatalog } = require('./fictional_catalog.cjs');
initializeApp({projectId});
const version = process.argv.find((arg) => arg.startsWith('--version='))?.split('=')[1] || 'demo-v1';
if (!/^[A-Za-z0-9_-]{1,80}$/.test(version)) throw new Error('Invalid catalog version');
registerCatalog(getFirestore(), version, fictionalCatalog(process.argv.includes('--scale')))
  .then(() => { console.log('Fictional catalog registered in local emulator:', version); process.exitCode = 0; })
  .catch((error) => { console.error(error.message); process.exitCode = 1; });
