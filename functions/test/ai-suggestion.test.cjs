'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const {registerCatalog}=require('../../tools/fictional_catalog.cjs');
const {operationsCatalog,operationRequest}=require('../../tools/operations_fixture.cjs');
const {confirm}=require('../schedule-service');
const {setStaffAbsence}=require('../staff-absence-service');
const {suggest,assembleSuggestion,guardSuggestionEnvironment}=require('../suggestion-service');
if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||''))throw Error('Demo loopback Emulator required');

test('AI recommendation: read-only 20 staff / 80 passengers, fixed responses only',async t=>{
  const app=initializeApp({projectId:'demo-ai-suggestions'},'ai-test');
  const db=getFirestore(app),catalog=operationsCatalog(),date='2026-12-07';
  const env={...process.env,FUNCTIONS_EMULATOR:'true'};
  const request=operationRequest(catalog,date,'morning','ai-v1',randomUUID());
  let input;
  const rejects=(p,code)=>assert.rejects(p,e=>e.code===code);
  try {
    await registerCatalog(db,'ai-v1',catalog);
    await db.doc('users/admin').create({role:'admin',active:true});
    await db.doc('users/staff').create({role:'staff',active:true,staffId:'s1'});
    await confirm(db,'admin',request);
    await setStaffAbsence(db,'admin',{date,staffId:'s1',periods:['morning'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion:'ai-v1'});
    input=structuredClone(request);input.expectedVersion=1;
    input.expectedAvailabilityVersions=Object.fromEntries(catalog.staff.map(s=>[s.id,s.id==='s1'?1:0]));
    input.absentIds=['p2'];input.routes[0].passengerIds=['p1','p3'];delete input.routes[0].estimatedVisitMinutes.p2;
    const answer=()=>({routes:input.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId==='s1'?'s3':r.staffId,passengerIds:[...r.passengerIds]})),reasons:['결근 직원 코스를 예비 직원에게 인계']});
    const before=await db.doc(`schedules/${date}_morning`).get();
    await t.test('production / non-loopback / unauthenticated / staff blocked before generation',async()=>{
      assert.throws(()=>guardSuggestionEnvironment({projectId:'senior-transport-app'},env),e=>e.code==='failed-precondition');
      assert.throws(()=>guardSuggestionEnvironment(db,{...env,FIRESTORE_EMULATOR_HOST:'remote:8080'}),e=>e.code==='failed-precondition');
      let calls=0;const generate=async()=>{calls++;return answer();};
      await rejects(suggest(db,null,input,{env,generate}),'unauthenticated');
      await rejects(suggest(db,'staff',input,{env,generate}),'permission-denied');
      assert.equal(calls,0);
    });
    await t.test('valid absence replacement / within-course order preserves protected values and returns time warnings',async()=>{
      const proposal=answer();
      proposal.routes[0].passengerIds=['p3','p1'];
      let calls=0;
      const result=await suggest(db,'admin',input,{env,generate:async data=>{
        calls++;assert.ok(!data.availableStaffIds.includes('s1'));assert.ok(data.availableStaffIds.includes('s3'));
        assert.ok(!JSON.stringify(data).includes('address'));return proposal;
      }});
      assert.equal(calls,1);assert.equal(result.routes.length,19);
      assert.equal(result.routes.flatMap(r=>r.passengerIds).length,79);
      assert.equal(result.routes[0].staffId,'s3');assert.ok(result.warnings.length>0);
      assert.ok(result.routes.every(r=>Object.keys(r).length===3));
      const move=structuredClone(proposal);
      move.routes[0].passengerIds=['p3'];move.routes.find(r=>r.staffId==='s4').passengerIds.push('p1');
      // An absence handoff alone is not a reason for unrelated membership edits.
      await assert.rejects(suggest(db,'admin',input,{env,generate:async()=>move}),e=>e.code==='invalid-argument'&&e.details?.violation==='REASSIGNMENT_NOT_JUSTIFIED');
      const merged=assembleSuggestion(input,move,catalog,['s1']);
      const target=merged.routes.find(r=>r.staffId==='s4');
      assert.equal(target.estimatedVisitMinutes.p1,input.routes[0].estimatedVisitMinutes.p1);
      assert.equal(target.vehicleId,input.routes.find(r=>r.staffId==='s4').vehicleId);
      assert.deepEqual((await before.ref.get()).data(),before.data());
      assert.ok((await before.ref.get()).updateTime.isEqual(before.updateTime));
      assert.equal((await db.collection('staffAvailability/'+date+'/staff').get()).size,1);
    });
    await t.test('missing course/person, duplicate IDs/owners, absent owner, invalid reference, capacity and forbidden fields rejected',async()=>{
      for(const mutate of [
        a=>a.routes.pop(),a=>a.routes[0].passengerIds.pop(),
        a=>a.routes[1].passengerIds.push('p1'),a=>a.routes[0].passengerIds.push('p1'),
        a=>a.routes[0].staffId='s2',a=>a.routes[0].staffId='s1',a=>a.routes[0].staffId='unknown',
        a=>a.routes[0].passengerIds.push('unknown'),a=>a.routes[0].passengerIds.push('p2'),
        a=>a.routes[0].vehicleId='v2',a=>a.routes[0].estimatedVisitMinutes={},a=>a.absentIds=[],
        a=>{const target=a.routes.find(r=>r.staffId==='s4');target.passengerIds.push(...a.routes[0].passengerIds);a.routes[0].passengerIds=[];},
      ]) {
        const bad=answer();mutate(bad);
        await rejects(suggest(db,'admin',input,{env,generate:async()=>bad}),'invalid-argument');
      }
      assert.ok((await before.ref.get()).updateTime.isEqual(before.updateTime));
    });
    await t.test('API failure preserves every schedule and no recommendation history is saved',async()=>{
      await rejects(suggest(db,'admin',input,{env,generate:async()=>{throw new HttpsError('unavailable','fixed offline response');}}),'unavailable');
      assert.ok((await before.ref.get()).updateTime.isEqual(before.updateTime));
      assert.equal((await db.collection(`schedules/${date}_morning/commits`).get()).size,1);
      assert.equal((await db.collection('aiSuggestions').get()).size,0);
    });
    await t.test('absence changes during model request reject the old recommendation',async()=>{
      await rejects(suggest(db,'admin',input,{env,generate:async()=>{
        await setStaffAbsence(db,'admin',{date,staffId:'s3',periods:['morning'],absent:true,expectedVersion:0,requestId:randomUUID(),catalogVersion:'ai-v1'});
        return answer();
      }}),'aborted');
      assert.ok((await before.ref.get()).updateTime.isEqual(before.updateTime));
      await setStaffAbsence(db,'admin',{date,staffId:'s3',periods:['morning'],absent:false,expectedVersion:1,requestId:randomUUID(),catalogVersion:'ai-v1'});
      input.expectedAvailabilityVersions.s3=2;
    });
    await t.test('concurrent confirmation rejects recommendation generated from an earlier version',async()=>{
      await rejects(suggest(db,'admin',input,{env,generate:async()=>{
        const replacement=structuredClone(input);replacement.requestId=randomUUID();replacement.routes[0].staffId='s3';
        await confirm(db,'admin',replacement);return answer();
      }}),'aborted');
      assert.equal((await before.ref.get()).data().version,2);
    });
    await t.test('approved proposal needs time review before confirmation, then staff projection gets the result',async()=>{
      const day='2026-12-08';
      const draft=operationRequest(catalog,day,'morning','ai-v1',randomUUID());
      draft.expectedAvailabilityVersions=Object.fromEntries(catalog.staff.map(s=>[s.id,0]));
      const proposal={routes:draft.routes.map((r,i)=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:i===0?[...r.passengerIds].reverse():[...r.passengerIds]})),reasons:['테스트 방문 순서 조정']};
      const result=await suggest(db,'admin',draft,{env,generate:async()=>proposal});
      assert.ok(result.warnings.length>0);
      const merged=assembleSuggestion(draft,proposal,catalog,[]);
      const approved={...draft,routes:merged.routes};
      await rejects(confirm(db,'admin',approved),'invalid-argument');
      assert.equal((await db.doc(`schedules/${day}_morning`).get()).exists,false);
      // The administrator's separate B-1/B-2 review supplies these new times.
      const first=approved.routes[0];
      first.estimatedVisitMinutes=Object.fromEntries(first.passengerIds.map((id,i)=>[id,535+5*i]));
      first.estimatedVisitSources=Object.fromEntries(first.passengerIds.map(id=>[id,'fixedInterval']));
      assert.equal((await confirm(db,'admin',approved)).version,1);
      const own=(await db.doc(`staffSchedules/s1/days/${day}_morning`).get()).data();
      assert.deepEqual(own.routes,[first]);
      assert.equal(own.version,1);
      assert.equal((await db.doc(`schedules/${day}_afternoon`).get()).exists,false);
    });
    await t.test('location-aware Gemini input, measured improvement and unchanged result are read-only and truthfully explained',async()=>{
      const located=operationsCatalog({withLocations:true});
      await registerCatalog(db,'geo-v1',located);
      const draft=operationRequest(located,'2026-12-09','morning','geo-v1',randomUUID());
      draft.expectedAvailabilityVersions=Object.fromEntries(located.staff.map(s=>[s.id,0]));
      const result=await suggest(db,'admin',draft,{env,generate:async payload=>{
        assert.equal(payload.locationModel.passengers.length,80);
        assert.ok(payload.locationModel.passengers.every(p=>Number.isFinite(p.xKm)&&Number.isFinite(p.yKm)));
        assert.ok(!JSON.stringify(payload).includes('address'));
        return {routes:payload.locationModel.heuristicCandidate.routes.map(r=>({...r,staffId:draft.routes.find(old=>old.baseRouteId===r.baseRouteId).staffId})),reasons:['근거 없는 99% 단축 주장']};
      }});
      assert.ok(result.distanceComparison.afterKm<result.distanceComparison.beforeKm);
      assert.ok(result.reasons.every(r=>!r.includes('99%')));
      const same=await suggest(db,'admin',draft,{env,generate:async()=>({routes:draft.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:r.passengerIds})),reasons:['근거 없는 99% 단축 주장']})});
      assert.equal(same.distanceComparison.beforeKm,same.distanceComparison.afterKm);
      assert.ok(same.reasons[0].includes('개선이 확인되지'));
      assert.equal((await db.doc(`schedules/${draft.date}_morning`).get()).exists,false);
    });
  } finally {await db.terminate();await deleteApp(app);}
});
