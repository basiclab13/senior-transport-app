'use strict';
const {createRequire} = require('node:module');
const {resolve} = require('node:path');
const {isDeepStrictEqual} = require('node:util');
const {randomUUID} = require('node:crypto');
const {operationsCatalog,operationRequest} = require('./operations_fixture.cjs');
const {registerCatalog} = require('./fictional_catalog.cjs');

function guard(env=process.env) {
  if (env.GCLOUD_PROJECT!=='demo-senior-transport' ||
      !['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST'].every((key)=>/^(127\.0\.0\.1|localhost):\d+$/.test(env[key]||''))) {
    throw new Error('Only demo-senior-transport and loopback Auth/Firestore Emulators are allowed');
  }
}

async function prepare(password) {
  guard();
  if (typeof password!=='string'||password.length<12) throw new Error('Supply a local-only password of at least 12 characters');
  const requireFunctions=createRequire(resolve(__dirname,'../functions/package.json'));
  const {initializeApp,deleteApp}=requireFunctions('firebase-admin/app');
  const {getAuth}=requireFunctions('firebase-admin/auth');
  const {getFirestore}=requireFunctions('firebase-admin/firestore');
  const {confirm}=require('../functions/schedule-service');
  const app=initializeApp({projectId:process.env.GCLOUD_PROJECT},`operations-${randomUUID()}`);
  const db=getFirestore(app); const auth=getAuth(app);
  const catalog=operationsCatalog(); const version='operations-20x80-v1';
  const accounts=[];
  let createdAccounts=0,createdSchedules=0;
  try {
    const parent=await db.doc(`catalogs/${version}`).get();
    if (!parent.exists) {
      const settings=await db.doc('settings/schedules').get();
      if (settings.exists) throw new Error('Existing emulator settings detected: use a fresh dedicated session');
      await registerCatalog(db,version,catalog);
    } else {
      if (!isDeepStrictEqual(parent.data(),{ready:true,fictional:true,schemaVersion:1}) ||
          (await db.doc('settings/schedules').get()).data()?.catalogVersion!==version) throw new Error('Existing fixture/settings conflict');
      for (const [collection,items] of Object.entries(catalog)) {
        const docs=await db.collection(`catalogs/${version}/${collection}`).get();
        if (docs.size!==items.length) throw new Error('Existing fixture count conflict');
        for (const {id,...data} of items) if (!isDeepStrictEqual(docs.docs.find((d)=>d.id===id)?.data(),data)) throw new Error('Existing fixture content conflict');
      }
    }
    for (const entry of [{role:'admin'},...catalog.staff.map((s)=>({role:'staff',staffId:s.id}))]) {
      const email=`ops-${entry.staffId||'admin'}@example.invalid`;
      let user;
      try {user=await auth.getUserByEmail(email);} catch(error) {
        if (error.code!=='auth/user-not-found') throw error;
        user=await auth.createUser({email,password}); createdAccounts++;
      }
      const ref=db.doc(`users/${user.uid}`); const profile=await ref.get();
      const expected={active:true,...entry};
      if (user.disabled || (profile.exists&&!isDeepStrictEqual(profile.data(),expected))) throw new Error('Existing account/profile conflict');
      if (!profile.exists) await ref.create(expected);
      accounts.push({email,uid:user.uid,...entry});
    }
    const admin=accounts.find((a)=>a.role==='admin');
    const wall=new Date(Date.now()+9*3600000);
    const today=wall.toISOString().slice(0,10);
    const tomorrow=new Date(Date.UTC(wall.getUTCFullYear(),wall.getUTCMonth(),wall.getUTCDate()+1)).toISOString().slice(0,10);
    for (const date of [today,tomorrow]) for (const period of ['morning','afternoon']) {
      if (!(await db.doc(`schedules/${date}_${period}`).get()).exists) {
        await confirm(db,admin.uid,operationRequest(catalog,date,period,version,randomUUID())); createdSchedules++;
      }
    }
    return {projectId:process.env.GCLOUD_PROJECT,version,today,tomorrow,createdAccounts,createdSchedules,
      counts:{staff:catalog.staff.length,vehicles:catalog.vehicles.length,passengers:catalog.passengers.length,baseRoutes:catalog.baseRoutes.length},accounts};
  } finally {await db.terminate();await deleteApp(app);}
}

if (require.main===module) {
  prepare(process.env.EMULATOR_USER_PASSWORD).then(({accounts,...summary})=>console.log(JSON.stringify({...summary,accounts:accounts.length},null,2)))
    .catch(()=>{console.error('Local fixture preparation failed; check demo project, loopback emulators, password and existing fixture conflicts. No credentials are printed.');process.exitCode=1;});
}
module.exports={prepare,guard};
