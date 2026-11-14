'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {getDoc,doc,setDoc}=require('firebase/firestore');
const {readFileSync}=require('node:fs');
const {registerCatalog}=require('../../tools/fictional_catalog.cjs');
const {operationsCatalog,operationRequest}=require('../../tools/operations_fixture.cjs');
const {productionSuggest}=require('../production-ai-service');
const {reserve,claim,finish}=require('../ai-request-policy');
const {anonymize}=require('../ai-privacy');

if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||''))throw Error('Demo loopback Emulator required');
test('production AI policy with simulated Gemini, 20 staff / 80 passengers',async t=>{
  const projectId='demo-production-ai-policy';
  const app=initializeApp({projectId},projectId),db=getFirestore(app);
  const [host,port]=process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const rules=await initializeTestEnvironment({projectId,firestore:{host,port:Number(port),rules:readFileSync('../firestore.rules','utf8')}});
  const catalog=operationsCatalog({withLocations:true}),version='approved-fictional-v1';
  await registerCatalog(db,version,catalog);
  for(const [id,role]of [['adminA','admin'],['adminB','admin'],['staffA','staff']])await db.doc(`users/${id}`).set({role,active:true,staffId:'s1'});
  const control=db.doc('_aiControl/config');
  const base={mode:'test',allowedAdminUids:['adminA','adminB'],allowedCatalogVersions:[version],cooldownSeconds:1};
  let now=Date.parse('2027-01-01T00:00:00Z'),calls=0;
  const clock=()=>now;
  const nextDay=()=>{now+=86400000;};
  const request=()=>({...operationRequest(catalog,'2026-12-07','morning',version,randomUUID()),
    expectedAvailabilityVersions:Object.fromEntries(catalog.staff.map(s=>[s.id,0]))});
  const answer=input=>({routes:input.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:r.passengerIds})),reasons:['모의 응답']});
  const generate=async input=>{calls++;return answer(input);};
  const run=(input=request(),options={},uid='adminA')=>productionSuggest(db,uid,input,{clock,generate,...options});
  const rejects=(p,code)=>assert.rejects(p,e=>e.code===code);
  try {
    await t.test('default off, role/allowlist/catalog checks and optional App Check fail before API',async()=>{
      await rejects(run(),'failed-precondition');
      await control.set(base);
      await rejects(run(request(),{},null),'unauthenticated');
      await rejects(run(request(),{},'staffA'),'permission-denied');
      await control.set({...base,allowedAdminUids:['adminB']});await rejects(run(),'permission-denied');
      await control.set({...base,allowedCatalogVersions:[]});await rejects(run(),'permission-denied');
      await control.set({...base,requireAppCheck:true});await rejects(run(),'unauthenticated');
      assert.equal(calls,0);
      await run(request(),{app:{appId:'verified-test-app'}});
      assert.equal(calls,1);
      await control.set(base);nextDay();
    });
    await t.test('outbound uses fresh aliases, no original IDs or private fields, result is read-only',async()=>{
      let first;
      const input=request(),logs=[];
      const verify=async value=>{
        calls++;first=value;
        const wire=JSON.stringify(value);
        for(const item of [...catalog.staff,...catalog.passengers,...catalog.vehicles,...catalog.baseRoutes])assert.ok(!wire.includes(JSON.stringify(item.id)));
        for(const key of ['date','email','name','address','note','estimatedVisitMinutes','estimatedVisitSources','uid'])assert.ok(!wire.includes(`"${key}":`));
        assert.equal(value.locationModel,undefined); // Explicit operator opt-in required for coordinates.
        return answer(value);
      };
      const result=await run(input,{generate:verify,log:r=>logs.push(r)});
      assert.deepEqual(result.routes.map(r=>r.passengerIds),input.routes.map(r=>r.passengerIds));
      assert.equal((await db.collection('schedules').get()).empty,true);
      assert.equal((await db.collection('staffSchedules').get()).empty,true);
      assert.ok(!JSON.stringify(logs).includes('adminA'));
      now+=2000;
      await run(request(),{generate:async value=>{assert.notEqual(value.routes[0].baseRouteId,first.routes[0].baseRouteId);return answer(value);}});
      const records=await db.collection('_aiRequests').get();
      for(const r of records.docs)assert.ok(!JSON.stringify(r.data()).includes('passengerIds'));
      nextDay();
    });
    await t.test('privacy allowlist strips injected fields, maps locations, rejects unknown IDs and forbidden changes',async()=>{
      await control.set({...base,allowFictionalLocations:true});
      await run(request(),{generate:async input=>{
        assert.ok(input.locationModel);assert.ok(input.locationModel.passengers.every(p=>p.id.startsWith('passenger_')));
        const p=anonymize({...input,date:'2026-12-07',vehicles:input.vehicles.map(v=>({...v,email:'private@example.invalid'}))});
        assert.ok(!JSON.stringify(p.input).includes('private@example.invalid'));
        return answer(input);
      }});
      now+=2000;
      await rejects(run(request(),{generate:async input=>{const r=answer(input);r.routes[0].staffId='s1';return r;}}),'invalid-argument');
      now+=2000;
      await rejects(run(request(),{generate:async input=>{const r=answer(input);r.routes[0].vehicleId='v1';return r;}}),'invalid-argument');
      await control.set(base);nextDay();
    });
    await t.test('same ID, changed payload, completed/error/timeout requests never call Gemini again',async()=>{
      const input=request();let count=0;
      const mock=async data=>{count++;return answer(data);};
      await run(input,{generate:mock});
      await rejects(run(input,{generate:mock}),'already-exists');
      await rejects(run({...input,excludedIds:['p1']},{generate:mock}),'invalid-argument');
      // A valid modified request is still rejected by its permanent request ID.
      const changed=structuredClone(input);
      changed.routes[0].estimatedVisitMinutes[changed.routes[0].passengerIds[0]]+=1;
      await rejects(run(changed,{generate:mock}),'already-exists');
      assert.equal(count,1);now+=2000;
      const failure=request();const broken=async()=>{count++;throw Error('DO_NOT_LOG_KEY_OR_BODY');};
      const logs=[];
      await rejects(run(failure,{generate:broken,log:r=>logs.push(r)}),'unavailable');
      await rejects(run(failure,{generate:mock}),'already-exists');
      assert.ok(!JSON.stringify(logs).includes('DO_NOT_LOG'));
      now+=2000;
      const timeout=request();
      await rejects(run(timeout,{generate:async()=>{count++;now+=121000;throw Error('timeout');}}),'unavailable');
      await rejects(run(timeout,{generate:mock}),'already-exists');
      assert.equal(count,3);nextDay();
    });
    await t.test('abandoned reservation, in-flight crash and expired lease cannot reopen an ID',async()=>{
      const input=request(),ticket=await reserve(db,'adminA',input,undefined,now);
      now+=121000;await rejects(run(input),'already-exists');
      await rejects(claim(db,ticket,now),'aborted');
      const second=request(),active=await reserve(db,'adminA',second,undefined,now);
      await claim(db,active,now);
      now+=121000;await rejects(run(second),'already-exists');
      await rejects(claim(db,active,now),'aborted');
      assert.equal(await finish(db,active,true,now),false);
      await run();nextDay();
    });
    await t.test('concurrent identical requests invoke once; live reservation blocks a different request',async()=>{
      let entered;const ready=new Promise(r=>{entered=r;});let release;
      const wait=new Promise(r=>{release=r;});const input=request();let count=0;
      const pending=run(input,{generate:async data=>{count++;entered();await wait;return answer(data);}});
      await ready;
      await rejects(run(input),'already-exists');
      await rejects(run(request(),{},'adminB'),'resource-exhausted');
      release();await pending;assert.equal(count,1);nextDay();
    });
    await t.test('project and admin daily limits are enforced transactionally and cooldown persists',async()=>{
      await control.set({...base,projectDailyLimit:2,adminDailyLimit:1});
      await run();now+=2000;await rejects(run(),'resource-exhausted');
      await run(request(),{},'adminB');now+=2000;
      await rejects(run(request(),{},'adminB'),'resource-exhausted');
      const day=new Date(now+9*3600000).toISOString().slice(0,10);
      assert.equal((await db.doc(`_aiUsage/${day}`).get()).data().count,2);
      nextDay();await control.set({...base,cooldownSeconds:30});
      await run();await rejects(run(),'resource-exhausted');now+=31000;await run();
      nextDay();await control.set(base);
    });
    await t.test('racing requests cannot overshoot project or administrator caps',async()=>{
      await control.set({...base,projectDailyLimit:1});
      let results=await Promise.allSettled([run(),run(request(),{},'adminB')]);
      assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
      assert.equal(results.find(r=>r.status==='rejected').reason.code,'resource-exhausted');
      nextDay();await control.set({...base,adminDailyLimit:1});
      results=await Promise.allSettled([run(),run()]);
      assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
      assert.equal(results.find(r=>r.status==='rejected').reason.code,'resource-exhausted');
      nextDay();await control.set(base);
    });
    await t.test('corrupt usage, inactive accounts and non-fictional catalog fail closed before generation',async()=>{
      const before=calls;
      const day=new Date(now+9*3600000).toISOString().slice(0,10);
      await db.doc(`_aiUsage/${day}`).set({count:-1,admins:{},activeUntilMs:0});
      await rejects(run(),'failed-precondition');nextDay();
      await db.doc('users/adminA').update({active:false});await rejects(run(),'permission-denied');
      await db.doc('users/adminA').update({active:true});
      await db.doc(`catalogs/${version}`).update({fictional:false});await rejects(run(),'failed-precondition');
      await db.doc(`catalogs/${version}`).update({fictional:true});
      assert.equal(calls,before);
    });
    await t.test('context changes, revoked approval and invalid proposals preserve schedules',async()=>{
      await rejects(run(request(),{generate:async input=>{const r=answer(input);r.routes[1].passengerIds.push(r.routes[0].passengerIds[0]);return r;}}),'invalid-argument');
      now+=2000;
      await rejects(run(request(),{generate:async input=>{
        await db.doc('staffAvailability/2026-12-07/staff/s1').set({schemaVersion:1,date:'2026-12-07',staffId:'s1',version:1,unavailablePeriods:['morning']});
        return answer(input);
      }}),'aborted');
      // Use a new valid date for remaining tests; no absence records are deleted.
      now+=2000;const other=request();other.date='2026-12-14';
      await rejects(run(other,{generate:async input=>{await control.set({...base,mode:'off'});return answer(input);}}),'failed-precondition');
      await control.set(base);
      assert.equal((await db.collection('schedules').get()).empty,true);
    });
    await t.test('existing rules deny clients all AI control, usage and request bookkeeping',async()=>{
      for(const uid of ['adminA','staffA'])for(const path of ['_aiControl/config','_aiUsage/day','_aiRequests/request']) {
        const client=rules.authenticatedContext(uid).firestore();
        await assertFails(getDoc(doc(client,path)));await assertFails(setDoc(doc(client,path),{mode:'test'}));
      }
    });
  } finally {await rules.cleanup();await deleteApp(app);}
});
