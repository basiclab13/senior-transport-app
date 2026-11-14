'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const {spawnSync}=require('node:child_process');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,getDoc}=require('firebase/firestore');
const {VERSION,COUNTS,buildManifest,makePlan,requestFor,scenario,SCENARIOS}=require('../../tools/ai25_fixture.cjs');
const {registerAi25}=require('../../tools/ai25_registration.cjs');
const {parse}=require('../../tools/register-ai25-catalog.cjs');
const {validateSchedule}=require('../validation');
const {confirm}=require('../schedule-service');
const {setStaffAbsence}=require('../staff-absence-service');
const {suggest}=require('../suggestion-service');
const {productionSuggest}=require('../production-ai-service');
const {geometryForCatalog,distanceHint,compareDistance}=require('../schedule-distance');
const manifest=JSON.parse(readFileSync('../docs/fixtures/ai-test-25x80-v1.baseline.json','utf8'));
const plan=makePlan(manifest);
const loopback=process.env.FIRESTORE_EMULATOR_HOST;
if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||!/^127\.0\.0\.1:\d+$/.test(loopback||''))throw Error('Demo Emulator required');
const guardedEnv=project=>({FIRESTORE_EMULATOR_HOST:loopback,GCLOUD_PROJECT:project});

test('25/80 fixture is reproducible, unique, complete, full, and does not replace existing fixtures',()=>{
  assert.deepEqual(manifest,buildManifest());assert.deepEqual(plan.counts,COUNTS);assert.equal(plan.documents.length,165);
  const c=manifest.collections;
  assert.equal(new Set([...c.staff,...c.passengers].map(p=>p.name)).size,105);
  assert.ok([...c.staff,...c.passengers,...c.vehicles].every(p=>!p.name.includes('가상')));
  assert.equal(c.vehicles.every(v=>v.passengerCapacity===4),true);
  for(const period of ['morning','afternoon']){
    const input=requestFor(c,'2026-12-07',period);
    assert.equal(input.routes.length,20);assert.equal(input.routes.every(r=>r.passengerIds.length===4),true);
    assert.equal(new Set(input.routes.map(r=>r.staffId)).size,20);assert.equal(new Set(input.routes.map(r=>r.vehicleId)).size,20);
    assert.equal(new Set(input.routes.flatMap(r=>r.passengerIds)).size,80);validateSchedule(input,c);
  }
  assert.equal(manifest.metadata.fixture.reserveStaffIds.length,5);
  assert.equal(require('../../tools/operations_fixture.cjs').operationsCatalog().baseRoutes.length,38);
  const geometry=geometryForCatalog(c,VERSION),input=requestFor(c);
  assert.deepEqual(distanceHint(input.routes,c,geometry).routes,input.routes.map(r=>({baseRouteId:r.baseRouteId,passengerIds:r.passengerIds})));
  for(const name of SCENARIOS){
    const stored=JSON.parse(readFileSync(`../docs/fixtures/ai-test-25x80-v1-scenarios/${name}.json`,'utf8')),s=scenario(name);
    assert.deepEqual(stored,{scenario:name,input:s.input,proposal:s.proposal,absentStaffIds:s.absentStaffIds||[]});
  }
});
test('CLI defaults offline, requires explicit approvals, and keeps old registration locked to 15 docs',()=>{
  assert.equal(parse([],{}).plan,true);
  assert.equal(parse(['--project','senior-transport-app'],{}).apply,false);
  for(const args of [['--project','wrong-project'],['--project','senior-transport-app','--apply','--confirm-project','senior-transport-app'],
    ['--project','demo-ai25','--apply'],['--project','demo-ai25','--apply','--confirm-project','other'],['--project','demo-ai25','--dry-run','--apply'],['--force']])assert.throws(()=>parse(args,{}));
  assert.throws(()=>parse(['--project','demo-ai25'],{FIRESTORE_EMULATOR_HOST:'remote:8080'}));
  const run=spawnSync(process.execPath,['../tools/register-ai25-catalog.cjs'],{encoding:'utf8'});
  assert.equal(run.status,0);assert.equal(JSON.parse(run.stdout).firebaseAccess,false);
  const old=require('../../tools/initial-catalog-registration.cjs');
  assert.throws(()=>old.makePlan(manifest));
  const oldPlan=old.makePlan(JSON.parse(readFileSync('../docs/fixtures/deploy-test-v2.baseline.json','utf8')));
  assert.equal(oldPlan.documents.length,15);
  const broken=structuredClone(manifest);broken.collections.vehicles[0].passengerCapacity=5;
  assert.throws(()=>makePlan(broken));
});
test('create-only catalog registration is atomic/idempotent and never touches pointers, users or schedules',async()=>{
  const app=initializeApp({projectId:'demo-ai25-registration'},'ai25-register'),db=getFirestore(app),env=guardedEnv(db.projectId);
  try{
    const sentinels={'settings/schedules':{catalogVersion:'deploy-test-v2'},'users/keep-account':{active:true,role:'staff',staffId:'s3'},
      'schedules/2026-12-07_morning':{version:77,catalogVersion:'deploy-test-v2'},'catalogs/deploy-test-v2':{ready:true,fictional:true,schemaVersion:1}};
    for(const [path,data]of Object.entries(sentinels))await db.doc(path).create(data);
    assert.equal((await registerAi25(db,manifest,{env})).status,'DRY_RUN_OK');
    assert.equal((await db.doc(plan.parentPath).get()).exists,false);
    const concurrent=await Promise.all([registerAi25(db,manifest,{env,apply:true}),registerAi25(db,manifest,{env,apply:true})]);
    assert.deepEqual(concurrent.map(r=>r.status).sort(),['ALREADY_REGISTERED','APPLIED']);
    assert.ok(concurrent.every(r=>r.verified&&r.settingsWrites===0&&r.accountWrites===0&&r.scheduleWrites===0));
    for(const d of plan.documents)assert.deepEqual((await db.doc(d.path).get()).data(),d.data);
    for(const [path,data]of Object.entries(sentinels))assert.deepEqual((await db.doc(path).get()).data(),data);
    await db.doc(plan.documents[0].path).update({name:'기존 문서 보존 확인'});
    assert.equal((await registerAi25(db,manifest,{env,apply:true})).status,'BLOCKED_EXISTING_DATA');
    assert.equal((await db.doc(plan.documents[0].path).get()).data().name,'기존 문서 보존 확인');
    // A separately interrupted/orphaned catalog is also blocked, never repaired silently.
    const other=initializeApp({projectId:'demo-ai25-orphan'},'ai25-orphan'),otherDb=getFirestore(other);
    try{
      await otherDb.doc(plan.documents[0].path).create(plan.documents[0].data);
      assert.equal((await registerAi25(otherDb,manifest,{env:guardedEnv(otherDb.projectId),apply:true})).status,'BLOCKED_EXISTING_DATA');
      assert.equal((await otherDb.doc(plan.parentPath).get()).exists,false);
    }finally{await deleteApp(other);}
  }finally{await deleteApp(app);}
});
test('CLI dry-run/apply/repeat uses only the confirmed demo project and never creates a settings pointer',async()=>{
  const projectId='demo-ai25-cli',app=initializeApp({projectId},projectId),db=getFirestore(app);
  const env={...process.env,GCLOUD_PROJECT:projectId,GOOGLE_CLOUD_PROJECT:projectId,FIREBASE_CONFIG:JSON.stringify({projectId})};
  const invoke=args=>{
    const result=spawnSync(process.execPath,['../tools/register-ai25-catalog.cjs',...args],{env,encoding:'utf8'});
    assert.equal(result.status,0,'CLI should succeed in isolated demo namespace');return JSON.parse(result.stdout);
  };
  try{
    assert.equal(invoke(['--project',projectId]).status,'DRY_RUN_OK');
    assert.equal((await db.doc(plan.parentPath).get()).exists,false);
    const applied=invoke(['--project',projectId,'--apply','--confirm-project',projectId]);
    assert.equal(applied.status,'APPLIED');assert.equal(applied.createdChildDocuments,165);assert.equal(applied.verified,true);
    assert.equal(invoke(['--project',projectId,'--apply','--confirm-project',projectId]).status,'ALREADY_REGISTERED');
    const verified=invoke(['--project',projectId,'--verify']);
    assert.equal(verified.status,'VERIFIED');assert.equal(verified.createdChildDocuments,0);
    assert.equal((await db.doc('settings/schedules').get()).exists,false);
    assert.equal((await db.collection('users').get()).empty,true);assert.equal((await db.collection('schedules').get()).empty,true);
    const rejected=spawnSync(process.execPath,['../tools/register-ai25-catalog.cjs','--project','senior-transport-app','--apply','--confirm-project','senior-transport-app'],{env,encoding:'utf8'});
    assert.equal(rejected.status,2);assert.equal(JSON.parse(rejected.stderr).errorCode,'CATALOG_APPROVAL_REQUIRED');
  }finally{await deleteApp(app);}
});
test('all 25/80 scenarios: mock suggestion, preserved times, confirmation and own staff projection',async t=>{
  for(const [index,name]of SCENARIOS.entries())await t.test(name,async()=>{
    const projectId=`demo-ai25-scenario-${index}`,app=initializeApp({projectId},projectId),db=getFirestore(app);
    const [host,port]=loopback.split(':');
    const rules=await initializeTestEnvironment({projectId,firestore:{host,port:Number(port),rules:readFileSync('../firestore.rules','utf8')}});
    try{
      await registerAi25(db,manifest,{env:guardedEnv(projectId),apply:true});
      // First initialization in a NEW isolated namespace, not an existing pointer transition.
      await db.doc('settings/schedules').create({catalogVersion:VERSION});
      await db.doc('users/fixture-admin').create({role:'admin',active:true});
      await db.doc('users/fixture-staff').create({role:'staff',active:true,staffId:'s21'});
      const s=scenario(name),date=s.input.date;
      for(const period of ['morning','afternoon'])await confirm(db,'fixture-admin',requestFor(s.catalog,date,period,`seed-${period}`));
      const otherPeriod=(await db.doc(`schedules/${date}_afternoon`).get()).data();
      for(const staffId of s.absentStaffIds||[])await setStaffAbsence(db,'fixture-admin',{
        date,staffId,periods:['morning'],absent:true,expectedVersion:0,requestId:`absence-${staffId}`,catalogVersion:VERSION});
      s.input.expectedVersion=1;s.input.requestId=`suggest-${name}`;
      const before=(await db.doc(`schedules/${date}_morning`).get()).data();
      const options={env:{...process.env,FUNCTIONS_EMULATOR:'true'},generate:async()=>s.proposal};
      if(name==='six-staff-absent'){
        assert.equal(s.catalog.staff.length-s.absentStaffIds.length,19);
        await assert.rejects(suggest(db,'fixture-admin',s.input,options),e=>e.code==='invalid-argument');
        await assert.rejects(confirm(db,'fixture-admin',s.input),e=>e.code==='failed-precondition');
        assert.deepEqual((await db.doc(`schedules/${date}_morning`).get()).data(),before);return;
      }
      const result=await suggest(db,'fixture-admin',s.input,options);
      assert.deepEqual((await db.doc(`schedules/${date}_morning`).get()).data(),before);
      if(name==='unchanged')assert.deepEqual(result.routes,s.proposal.routes);
      if(name==='order-improvement'||name==='absence-capacity-improvement'){
        assert.ok(result.distanceComparison.afterKm<result.distanceComparison.beforeKm);
        assert.ok(result.warnings.length>0); // Non-blocking morning contact reminder.
      }
      const updated={...s.input,requestId:`confirm-${name}`,routes:result.routes.map(r=>{
        const old=s.input.routes.find(x=>x.baseRouteId===r.baseRouteId);
        const minutes=Object.assign({},...s.input.routes.map(x=>x.estimatedVisitMinutes));
        const sources=Object.assign({},...s.input.routes.map(x=>x.estimatedVisitSources||{}));
        return {...old,...r,estimatedVisitMinutes:Object.fromEntries(r.passengerIds.filter(id=>Object.hasOwn(minutes,id)).map(id=>[id,minutes[id]])),
          estimatedVisitSources:Object.fromEntries(r.passengerIds.filter(id=>Object.hasOwn(sources,id)).map(id=>[id,sources[id]]))};
      })};
      assert.equal((await confirm(db,'fixture-admin',updated)).version,2);
      assert.deepEqual((await db.doc(`schedules/${date}_afternoon`).get()).data(),otherPeriod);
      if(s.absentStaffIds?.length){
        const client=rules.authenticatedContext('fixture-staff').firestore();
        const own=await assertSucceeds(getDoc(doc(client,`staffSchedules/s21/days/${date}_morning`)));
        assert.equal(own.data().catalog.staff[0].name,'문예준');
        assert.equal(own.data().routes[0].vehicleId,'v1');assert.deepEqual(own.data().routes[0].passengerIds,['p1','p2','p3','p4']);
        assert.equal((await db.doc(`staffSchedules/s1/days/${date}_morning`).get()).exists,false);
        await assertFails(getDoc(doc(client,`staffSchedules/s2/days/${date}_morning`)));
      }
    }finally{await rules.cleanup();await deleteApp(app);}
  });
});
test('approved 25/80 catalog works with production privacy mapping and opt-in synthetic coordinates, without external API',async()=>{
  const projectId='demo-ai25-private',app=initializeApp({projectId},projectId),db=getFirestore(app);
  try{
    await registerAi25(db,manifest,{env:guardedEnv(projectId),apply:true});
    await db.doc('settings/schedules').create({catalogVersion:VERSION});await db.doc('users/fixture-admin').create({role:'admin',active:true});
    const control={mode:'test',allowedAdminUids:['fixture-admin'],allowedCatalogVersions:[VERSION],projectDailyLimit:1,adminDailyLimit:1,
      allowFictionalLocations:true,requireAppCheck:false,cooldownSeconds:30};
    await db.doc('_aiControl/config').create(control);
    const input=requestFor(manifest.collections);let calls=0;
    await productionSuggest(db,'fixture-admin',input,{generate:async data=>{
      calls++;assert.equal(data.routes.length,20);assert.equal(data.availableStaffIds.length,25);assert.equal(data.requiredPassengerIds.length,80);
      assert.ok(data.locationModel);const wire=JSON.stringify(data);
      for(const [collection,items]of Object.entries(manifest.collections))for(const item of items){
        assert.ok(!wire.includes(JSON.stringify(item.id)),collection);assert.ok(!wire.includes(item.name));}
      return {routes:data.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:r.passengerIds})),reasons:['고정 응답']};
    }});
    assert.equal(calls,1);assert.equal((await db.collection('schedules').get()).empty,true);
    assert.equal((await db.collection('staffSchedules').get()).empty,true);
  }finally{await deleteApp(app);}
});
test('25/80 capacity, duplicate assignment, missing passenger and visit time validation remain strict',()=>{
  for(const mutate of [
    r=>{const a=r.routes[0],b=r.routes[1];a.passengerIds.push(b.passengerIds.pop());},
    r=>{r.routes[1].staffId=r.routes[0].staffId;},r=>{r.routes[1].vehicleId=r.routes[0].vehicleId;},
    r=>{r.routes[0].passengerIds.pop();},r=>{r.routes[0].estimatedVisitMinutes.p2=-1;},
  ]){const input=requestFor(manifest.collections);mutate(input);assert.throws(()=>validateSchedule(input,manifest.collections));}
});
