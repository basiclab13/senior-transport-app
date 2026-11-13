'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {operationsCatalog,operationRequest}=require('../../tools/operations_fixture.cjs');
const {fictionalCatalog}=require('../../tools/fictional_catalog.cjs');
const {guard}=require('../../tools/prepare_operations_emulator.cjs');
const {validateSchedule}=require('../validation');

test('operational fixture retains baseline with exactly 20 staff, 20 vehicles, 80 passengers and 38 routes',()=>{
  const catalog=operationsCatalog();
  assert.deepEqual({staff:catalog.staff.length,vehicles:catalog.vehicles.length,passengers:catalog.passengers.length,baseRoutes:catalog.baseRoutes.length},
    {staff:20,vehicles:20,passengers:80,baseRoutes:38});
  for(const [collection,items] of Object.entries(fictionalCatalog(false))) {
    for(const item of items) assert.deepEqual(catalog[collection].find((d)=>d.id===item.id),item);
  }
  for(const period of ['morning','afternoon']) {
    const routes=catalog.baseRoutes.filter((r)=>r.period===period);
    assert.equal(routes.length,19);
    const ids=routes.flatMap((r)=>r.passengerIds);
    assert.equal(ids.length,80); assert.equal(new Set(ids).size,80);
  }
});

test('morning and afternoon operational scenarios validate; afternoon includes absent and excluded passengers',()=>{
  const catalog=operationsCatalog();
  for(const period of ['morning','afternoon']) {
    const request=operationRequest(catalog,'2026-11-16',period,'operations-20x80-v1','local-test');
    assert.doesNotThrow(()=>validateSchedule(request,catalog));
    assert.equal(request.routes.flatMap((r)=>r.passengerIds).length,period==='morning'?80:78);
  }
});

test('missing passenger, duplicate, full vehicle, unavailable staff and time conflict remain blocked',()=>{
  const catalog=operationsCatalog();
  for(const mutate of [
    (request)=>{request.routes.at(-1).passengerIds.pop();},
    (request)=>{request.routes[1].passengerIds.push('p1');},
    (request)=>{request.routes[0].passengerIds.push('p4');request.routes[1].passengerIds=request.routes[1].passengerIds.filter((id)=>id!=='p4');},
    (request)=>{request.routes[0].estimatedVisitMinutes.p2=530;},
    (request)=>{request.date='2026-11-13';request.routes[0].staffId='s3';},
    (request)=>{request.routes[1].vehicleId=request.routes[0].vehicleId;},
  ]) {
    const request=operationRequest(catalog,'2026-11-16','morning','operations-20x80-v1','local-test');
    mutate(request); assert.throws(()=>validateSchedule(request,catalog));
  }
});

test('operational preparation rejects production and non-loopback addresses before SDK initialization',()=>{
  assert.throws(()=>guard({GCLOUD_PROJECT:'senior-transport-app',FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099'}));
  assert.throws(()=>guard({GCLOUD_PROJECT:'demo-senior-transport',FIRESTORE_EMULATOR_HOST:'remote:8080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099'}));
  assert.doesNotThrow(()=>guard({GCLOUD_PROJECT:'demo-senior-transport',FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099'}));
});
