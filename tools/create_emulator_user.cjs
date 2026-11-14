"use strict";
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const projectId = process.env.GCLOUD_PROJECT;
if (![firestoreHost, authHost].every((host) => /^(127\.0\.0\.1|localhost):\d+$/.test(host || '')) || !projectId?.startsWith('demo-')) {
  throw new Error('Only loopback Auth/Firestore emulators and demo-* project IDs are supported');
}
const functionsRequire = require('node:module').createRequire(require('node:path').resolve(__dirname, '../functions/package.json'));
const { initializeApp } = functionsRequire('firebase-admin/app');
const { getAuth } = functionsRequire('firebase-admin/auth');
const { getFirestore } = functionsRequire('firebase-admin/firestore');
const { idPattern } = require('../functions/validation');
const [role, staffId] = process.argv.slice(2);
if (!['admin', 'staff'].includes(role) || (role === 'staff' && !idPattern.test(staffId || ''))) throw new Error('Usage: node tools/create_emulator_user.cjs admin|staff [staffId]');
const email = process.env.EMULATOR_USER_EMAIL;
const password = process.env.EMULATOR_USER_PASSWORD;
if (!email || !password) throw new Error('Set EMULATOR_USER_EMAIL and EMULATOR_USER_PASSWORD; credentials are never printed');
initializeApp({projectId});
async function main() {
  const db = getFirestore();
  if (role === 'staff') {
    const version = (await db.doc('settings/schedules').get()).data()?.catalogVersion;
    if (!idPattern.test(version || '') || (await db.doc(`catalogs/${version}/staff/${staffId}`).get()).data()?.active !== true) throw new Error('staffId does not reference an active employee');
  }
  const user = await getAuth().createUser({email, password});
  await db.doc(`users/${user.uid}`).create({active: true, role, ...(role === 'staff' ? {staffId} : {})});
  console.log('Local emulator account/profile created:', role);
}
main().catch(() => { console.error('Emulator account creation failed; check input and local emulator state.'); process.exitCode = 1; });
