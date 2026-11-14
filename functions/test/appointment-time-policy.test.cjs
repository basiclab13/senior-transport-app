'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {buildManifest,requestFor,VERSION}=require('../../tools/demo10_fixture.cjs');
const {registerCatalog}=require('../../tools/fictional_catalog.cjs');
const {validateSchedule,safeViolation}=require('../validation');
const {confirm}=require('../schedule-service');
const {productionSuggest}=require('../production-ai-service');
const {assembleSuggestion}=require('../suggestion-service');
const catalog=buildManifest().collections;
function request(period='morning'){
  const r=requestFor(catalog,'2026-12-07',period);r.requestId=randomUUID();
  const first=r.routes[0],ids=first.passengerIds;
  first.estimatedVisitMinutes={[ids[0]]:610,[ids[1]]:610,[ids[2]]:480};
  first.estimatedVisitSources={[ids[0]]:'manual',[ids[1]]:'fixedInterval'};
  first.startMinute=600;first.endMinute=540;
  return r;
}
for(const period of ['morning','afternoon'])test(`${period}: missing, equal, reverse, out-of-window and partial legacy window do not block`,()=>{
  assert.doesNotThrow(()=>validateSchedule(requestFor(catalog,'2026-12-07',period),catalog));
  const input=request(period),before=structuredClone(input);
  assert.doesNotThrow(()=>validateSchedule(input,catalog));assert.deepEqual(input,before);
  input.routes[0].startMinute=null;
  assert.doesNotThrow(()=>validateSchedule(input,catalog));
});
for(const [name,mutate,violation]of [
  ['negative minute',r=>r.estimatedVisitMinutes[r.passengerIds[0]]=-1,'VISIT_TIME_INVALID'],
  ['midnight overflow',r=>r.estimatedVisitMinutes[r.passengerIds[0]]=1440,'VISIT_TIME_INVALID'],
  ['fractional minute',r=>r.estimatedVisitMinutes[r.passengerIds[0]]=0.5,'VISIT_TIME_INVALID'],
  ['string minute',r=>r.estimatedVisitMinutes[r.passengerIds[0]]='09:30','VISIT_TIME_INVALID'],
  ['unknown source',r=>r.estimatedVisitSources[r.passengerIds[0]]='ai','ESTIMATE_SOURCE_INVALID'],
  ['orphan source',r=>r.estimatedVisitSources.unknown='manual','ESTIMATE_SOURCE_INVALID'],
  ['orphan time',r=>r.estimatedVisitMinutes.unknown=500,'ESTIMATE_REFERENCE_INVALID'],
  ['invalid retained window',r=>r.endMinute=1440,'OPERATING_WINDOW_INVALID'],
])test(`time data integrity still rejects ${name}`,()=>{
  const input=request();mutate(input.routes[0]);
  assert.throws(()=>validateSchedule(input,catalog),e=>e.code==='invalid-argument'&&safeViolation(e)===violation);
});
test('AI order and passenger transfer keep manual, calculated and sourceless records; times cannot be output',()=>{
  const input=request(),before=structuredClone(input);
  const answer={routes:input.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:[...r.passengerIds]})),reasons:[]};
  const moved=answer.routes[0].passengerIds.shift();answer.routes[1].passengerIds.push(moved);answer.routes[0].passengerIds.reverse();
  const result=assembleSuggestion(input,answer,catalog,[]);
  assert.equal(result.routes[1].estimatedVisitMinutes[moved],610);
  assert.equal(result.routes[1].estimatedVisitSources[moved],'manual');
  assert.equal(result.routes[0].estimatedVisitSources.p2,'fixedInterval');
  assert.equal(Object.hasOwn(result.routes[0].estimatedVisitSources,'p3'),false);
  assert.equal(result.warnings.length,1);assert.deepEqual(input,before);
  answer.routes[0].estimatedVisitMinutes={p2:999};
  assert.throws(()=>assembleSuggestion(input,answer,catalog,[]),e=>safeViolation(e)==='RESPONSE_FIELDS_FORBIDDEN');
});
if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||''))throw Error('Demo loopback required');
test('AM/PM confirm, production mock AI, staff projections and retry preserve legacy time data',async()=>{
  const app=initializeApp({projectId:'demo-appointment-policy'},'appointment-policy'),db=getFirestore(app);
  try{
    await registerCatalog(db,VERSION,catalog);
    await db.doc('users/admin').create({active:true,role:'admin'});
    await db.doc('users/staff').create({active:true,role:'staff',staffId:'s1'});
    await db.doc('attendance/s1/records/keep').create({keep:true});
    await db.doc('_aiControl/config').create({mode:'test',allowedAdminUids:['admin'],allowedCatalogVersions:[VERSION],projectDailyLimit:2,adminDailyLimit:2,cooldownSeconds:1,allowFictionalLocations:true,requireAppCheck:false});
    for(const period of ['morning','afternoon']){
      const original=request(period);await confirm(db,'admin',original);
      const first=structuredClone(original.routes[0]);
      const input={...original,requestId:randomUUID(),expectedVersion:1};
      let calls=0;
      const result=await productionSuggest(db,'admin',input,{clock:()=>Date.now()+(period==='afternoon'?86400000:0),generate:async data=>{
        calls++;const wire=JSON.stringify(data);
        for(const field of ['estimatedVisitMinutes','estimatedVisitSources','startMinute','endMinute','name','address'])assert.ok(!wire.includes(`"${field}":`));
        return {routes:data.routes.map((r,i)=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:i===0?[...r.passengerIds].reverse():r.passengerIds})),reasons:[]};
      }});
      assert.equal(calls,1);assert.equal(result.warnings.length,period==='morning'?1:0);
      assert.equal((await db.doc(`schedules/${input.date}_${period}`).get()).data().version,1);
      const answer={routes:result.routes,reasons:[]};
      const candidate=assembleSuggestion(input,answer,catalog,[]);
      const approved={...input,routes:candidate.routes};
      const results=await Promise.all([confirm(db,'admin',approved),confirm(db,'admin',approved)]);
      assert.ok(results.every(r=>r.version===2));
      const own=(await db.doc(`staffSchedules/s1/days/${input.date}_${period}`).get()).data();
      assert.deepEqual(own.routes[0].estimatedVisitMinutes,first.estimatedVisitMinutes);
      assert.deepEqual(own.routes[0].estimatedVisitSources,first.estimatedVisitSources);
      assert.equal(own.routes[0].startMinute,first.startMinute);assert.equal(own.routes[0].endMinute,first.endMinute);
      await assert.rejects(confirm(db,'admin',{...approved,requestId:randomUUID()}),{code:'aborted'});
      await assert.rejects(confirm(db,'staff',{...approved,requestId:randomUUID(),expectedVersion:2}),{code:'permission-denied'});
    }
    assert.deepEqual((await db.doc('attendance/s1/records/keep').get()).data(),{keep:true});
  }finally{await deleteApp(app);}
});
