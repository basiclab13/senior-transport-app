'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {buildManifest,requestFor,scenario,SCENARIOS}=require('../../tools/ai25_fixture.cjs');
const {registerAi25}=require('../../tools/ai25_registration.cjs');
const {fictionalCatalog,registerCatalog}=require('../../tools/fictional_catalog.cjs');
const {confirm}=require('../schedule-service');
const {suggest}=require('../suggestion-service');
const {productionSuggest}=require('../production-ai-service');
const {previewRequest,VERSION,MANIFEST_HASH,KIND}=require('../catalog-preview-context');
if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||''))throw Error('Demo Emulator required');
const manifest=buildManifest();
const envelope=name=>{const s=scenario(name);return {...s.input,requestId:randomUUID(),previewContext:{kind:KIND,scenario:name,manifestSha256:MANIFEST_HASH}};};
test('preview envelope is explicit, immutable and cannot be sent to the existing confirmation endpoint',async()=>{
  assert.equal(MANIFEST_HASH,require('../../tools/ai25_fixture.cjs').makePlan(manifest).manifestSha256);
  const input=envelope('unchanged');
  for(const mutate of [
    x=>{x.catalogVersion='deploy-test-v2';},x=>{x.expectedVersion=1;},x=>{x.previewContext.kind='normal';},
    x=>{x.previewContext.scenario='arbitrary';},x=>{x.previewContext.manifestSha256='changed';},
    x=>{x.previewContext.absentStaffIds=['s1'];},
  ]){const changed=structuredClone(input);mutate(changed);assert.throws(()=>previewRequest(changed),e=>e.code==='invalid-argument');}
  await assert.rejects(confirm({runTransaction:()=>{throw Error('Must not access DB');}},'admin',input),e=>e.code==='invalid-argument');
});
test('catalog preview never reads/writes operational schedules, settings or absence records; all scenarios stay isolated',async t=>{
  const projectId='demo-catalog-preview',app=initializeApp({projectId},projectId),db=getFirestore(app);
  let now=Date.parse('2027-02-01T00:00:00Z'),calls=0;
  const clock=()=>now;
  try{
    const old=fictionalCatalog(false);
    await registerCatalog(db,'deploy-test-v2',old);
    await db.doc('users/preview-admin').create({role:'admin',active:true});
    await db.doc('users/preview-staff').create({role:'staff',active:true,staffId:'s1'});
    const oldInput={date:'2026-12-07',period:'morning',catalogVersion:'deploy-test-v2',expectedVersion:0,requestId:'old-confirmed',absentIds:[],excludedIds:[],
      routes:old.baseRoutes.filter(r=>r.period==='morning').map(r=>({baseRouteId:r.id,staffId:r.staffId,vehicleId:r.vehicleId,passengerIds:r.passengerIds,estimatedVisitMinutes:{}}))};
    await confirm(db,'preview-admin',oldInput);
    await db.doc('staffAvailability/2026-12-07/staff/s1').create({schemaVersion:1,date:'2026-12-07',staffId:'s1',version:22,unavailablePeriods:['morning']});
    await registerAi25(db,manifest,{apply:true,env:{GCLOUD_PROJECT:projectId,FIRESTORE_EMULATOR_HOST:process.env.FIRESTORE_EMULATOR_HOST}});
    const control={mode:'test',allowedAdminUids:['preview-admin'],allowedCatalogVersions:[VERSION],cooldownSeconds:1,allowFictionalLocations:true};
    await db.doc('_aiControl/config').create(control);
    const protectedPaths=['settings/schedules','schedules/2026-12-07_morning','staffSchedules/s1/days/2026-12-07_morning',
      'users/preview-admin','users/preview-staff','staffAvailability/2026-12-07/staff/s1','catalogs/deploy-test-v2'];
    const before=await Promise.all(protectedPaths.map(async path=>[path,(await db.doc(path).get()).data()]));
    const isolated=new Proxy(db,{get(target,key){
      if(key==='doc'||key==='collection')return path=>{
        assert.ok(!/^(settings|schedules|staffSchedules|staffAvailability)\//.test(path),'preview must not read operational context');
        return target[key](path);
      };
      const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
    }});
    for(const name of SCENARIOS)await t.test(name,async()=>{
      now+=2000;const input=envelope(name),s=scenario(name);
      const available=s.catalog.staff.filter(p=>!(s.absentStaffIds||[]).includes(p.id)).map(p=>p.id);
      const required=s.catalog.baseRoutes.filter(r=>r.period===input.period).flatMap(r=>r.passengerIds).filter(id=>!input.absentIds.includes(id)&&!input.excludedIds.includes(id));
      const generate=async data=>{
        calls++;assert.equal(data.routes.length,20);assert.ok(data.locationModel);
        const wire=JSON.stringify(data);assert.ok(!wire.includes('previewContext'));assert.ok(!wire.includes(MANIFEST_HASH));
        for(const item of [...s.catalog.staff,...s.catalog.passengers]){assert.ok(!wire.includes(JSON.stringify(item.id)));assert.ok(!wire.includes(item.name));}
        const routeAliases=new Map(input.routes.map((r,i)=>[r.baseRouteId,data.routes[i].baseRouteId]));
        const staffAliases=new Map(available.map((id,i)=>[id,data.availableStaffIds[i]]));
        const passengerAliases=new Map(required.map((id,i)=>[id,data.requiredPassengerIds[i]]));
        return {routes:s.proposal.routes.map(r=>({baseRouteId:routeAliases.get(r.baseRouteId),
          staffId:staffAliases.get(r.staffId)||data.availableStaffIds[0],passengerIds:r.passengerIds.map(id=>passengerAliases.get(id))})),reasons:['모의 응답']};
      };
      if(name==='six-staff-absent')await assert.rejects(productionSuggest(isolated,'preview-admin',input,{generate,clock}),e=>e.code==='failed-precondition');
      else{
        const result=await productionSuggest(isolated,'preview-admin',input,{generate,clock});
        assert.deepEqual(result.previewContext,input.previewContext);assert.deepEqual(result.routes,s.proposal.routes);
        assert.equal(result.expectedVersion,0);
        if(name.includes('improvement'))assert.ok(result.distanceComparison.afterKm<result.distanceComparison.beforeKm);
      }
    });
    await t.test('normal requests still require the operational catalog and unchanged version',async()=>{
      const normal=envelope('unchanged');delete normal.previewContext;normal.expectedVersion=1;
      let generated=false;
      await assert.rejects(productionSuggest(db,'preview-admin',normal,{clock,generate:async()=>{generated=true;}}),e=>e.code==='failed-precondition');
      assert.equal(generated,false);
    });
    await t.test('preview authorization remains fail-closed without consuming usage or invoking the generator',async()=>{
      const usageBefore=(await db.collection('_aiUsage').get()).docs.map(d=>[d.id,d.data()]);
      const requestsBefore=(await db.collection('_aiRequests').get()).size;
      let generated=false;
      const options={clock,generate:async()=>{generated=true;throw Error('Must not generate');}};
      for(const [patch,code] of [
        [{mode:'off'},'failed-precondition'],
        [{mode:'enabled'},'failed-precondition'],
        [{allowedAdminUids:[]},'permission-denied'],
        [{allowedCatalogVersions:['deploy-test-v2']},'permission-denied'],
        [{requireAppCheck:true},'unauthenticated'],
      ]) {
        await db.doc('_aiControl/config').set({...control,...patch});
        await assert.rejects(productionSuggest(isolated,'preview-admin',envelope('unchanged'),options),e=>e.code===code);
      }
      await db.doc('_aiControl/config').delete();
      await assert.rejects(productionSuggest(isolated,'preview-admin',envelope('unchanged'),options),e=>e.code==='failed-precondition');
      await db.doc('_aiControl/config').set({...control,requireAppCheck:false});
      await db.doc('users/preview-admin').update({active:false});
      await assert.rejects(productionSuggest(isolated,'preview-admin',envelope('unchanged'),options),e=>e.code==='permission-denied');
      await db.doc('users/preview-admin').update({active:true});
      assert.equal(generated,false);
      assert.equal((await db.collection('_aiRequests').get()).size,requestsBefore);
      assert.deepEqual((await db.collection('_aiUsage').get()).docs.map(d=>[d.id,d.data()]),usageBefore);
      await db.doc('_aiControl/config').set(control);
    });
    await t.test('same request ID and quota still apply to previews',async()=>{
      now+=2000;const input=envelope('unchanged');
      const generate=async data=>({routes:data.routes.map(({baseRouteId,staffId,passengerIds})=>({baseRouteId,staffId,passengerIds})),reasons:[]});
      await productionSuggest(isolated,'preview-admin',input,{clock,generate});
      await assert.rejects(productionSuggest(isolated,'preview-admin',input,{clock,generate}),e=>e.code==='already-exists');
      await db.doc('_aiControl/config').update({projectDailyLimit:1});
      await assert.rejects(productionSuggest(isolated,'preview-admin',envelope('unchanged'),{clock,generate}),e=>e.code==='resource-exhausted');
      await db.doc('_aiControl/config').set(control);
    });
    await t.test('non-admin, mismatched virtual absence version, and changed catalog are rejected before generation',async()=>{
      const input=envelope('staff-absence');let generated=false;
      const options={clock,generate:async()=>{generated=true;}};
      await assert.rejects(productionSuggest(isolated,'preview-staff',input,options),e=>e.code==='permission-denied');
      input.expectedAvailabilityVersions.s1=0;
      await assert.rejects(productionSuggest(isolated,'preview-admin',input,options),e=>e.code==='aborted');
      await db.doc(`catalogs/${VERSION}/staff/s1`).update({name:'변경 감지'});
      await assert.rejects(productionSuggest(isolated,'preview-admin',envelope('unchanged'),options),e=>e.code==='failed-precondition');
      assert.equal(generated,false);
      await db.doc(`catalogs/${VERSION}/staff/s1`).update({name:manifest.collections.staff[0].name});
    });
    await t.test('catalog mutation during generation invalidates the result, without saving a schedule',async()=>{
      now+=2000;
      await assert.rejects(productionSuggest(isolated,'preview-admin',envelope('unchanged'),{clock,generate:async data=>{
        await db.doc(`catalogs/${VERSION}`).update({testData:false});
        return {routes:data.routes.map(({baseRouteId,staffId,passengerIds})=>({baseRouteId,staffId,passengerIds})),reasons:[]};
      }}),e=>e.code==='failed-precondition');
      await db.doc(`catalogs/${VERSION}`).update({testData:true});
    });
    await t.test('legacy Emulator AI supports the same explicit preview without removing its environment guard',async()=>{
      const input=envelope('unchanged'),s=scenario('unchanged');
      const result=await suggest(isolated,'preview-admin',input,{env:{...process.env,FUNCTIONS_EMULATOR:'true'},generate:async()=>s.proposal});
      assert.deepEqual(result.previewContext,input.previewContext);
    });
    for(const [path,data]of before)assert.deepEqual((await db.doc(path).get()).data(),data);
    const schedules=await db.collection('schedules').get();assert.equal(schedules.size,1);
    assert.equal(calls,6); // Infeasible scenario rejected before mock generation/quota.
  }finally{await deleteApp(app);}
});
