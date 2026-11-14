'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {operationsCatalog,operationRequest}=require('../../tools/operations_fixture.cjs');
const {validateSchedule}=require('../validation');
const {assembleSuggestion}=require('../suggestion-service');
const d=require('../schedule-distance');

test('80 deterministic fictional coordinates are optional; the existing immutable fixture stays byte-compatible',()=>{
  const old=operationsCatalog(),before=JSON.stringify(old);
  const located=operationsCatalog({withLocations:true});
  assert.equal(located.passengers.length,80);
  assert.ok(old.passengers.every(p=>p.fictionalLocation===undefined));
  assert.ok(located.passengers.every(p=>Number.isFinite(p.fictionalLocation.xKm)&&Number.isFinite(p.fictionalLocation.yKm)));
  assert.equal(new Set(located.passengers.map(p=>JSON.stringify(p.fictionalLocation))).size,80);
  assert.deepEqual(operationsCatalog({withLocations:true}),located);
  const reordered=d.withFictionalLocations({...old,baseRoutes:[...old.baseRoutes].reverse()});
  assert.deepEqual(reordered.passengers,located.passengers);
  assert.deepEqual(located.baseRoutes,old.baseRoutes);
  assert.equal(JSON.stringify(old),before);
  assert.equal(d.geometryForCatalog(old,'operations-20x80-v1').locations.size,80);
  assert.equal(d.geometryForCatalog(old,'other-catalog').locations.size,0);
});
test('distance is center-to-stops-to-center in km, with empty/single routes and missing coordinates handled honestly',()=>{
  const geometry={center:{xKm:0,yKm:0},locations:new Map([['a',{xKm:3,yKm:0}],['b',{xKm:3,yKm:4}]])};
  assert.equal(d.routeDistance([],geometry),0);
  assert.equal(d.routeDistance(['a'],geometry),6);
  assert.equal(d.routeDistance(['a','b'],geometry),12);
  assert.equal(d.routeDistance(['missing'],geometry),null);
  assert.equal(d.compareDistance([{passengerIds:['a']}],[{passengerIds:['missing']}],geometry),null);
});
test('bounded heuristic improves this fictional 20/80 scenario without changing protected assignments, coverage or capacities',()=>{
  const catalog=operationsCatalog({withLocations:true});
  const input=operationRequest(catalog,'2026-12-07','morning','geo-v1','unit-test');
  const geometry=d.geometryForCatalog(catalog,'geo-v1');
  const before=JSON.stringify(input);
  const hint=d.distanceHint(input.routes,catalog,geometry);
  assert.ok(hint.estimatedTotalKm<d.totalDistance(input.routes,geometry));
  assert.equal(new Set(hint.routes.flatMap(r=>r.passengerIds)).size,80);
  assert.ok(hint.routes.filter((r,i)=>JSON.stringify(r.passengerIds)!==JSON.stringify(input.routes[i].passengerIds)).length<=2);
  const answer={routes:hint.routes.map(r=>({...r,staffId:input.routes.find(old=>old.baseRouteId===r.baseRouteId).staffId})),reasons:['참고 후보']};
  const candidate=assembleSuggestion(input,answer,catalog,[]);
  validateSchedule({...input,routes:candidate.routes.map(r=>({...r,estimatedVisitMinutes:{},estimatedVisitSources:{}}))},catalog);
  for(let i=0;i<input.routes.length;i++) {
    assert.equal(candidate.routes[i].vehicleId,input.routes[i].vehicleId);
    assert.equal(candidate.routes[i].staffId,input.routes[i].staffId);
  }
  assert.equal(JSON.stringify(input),before);
});
test('missing/invalid coordinates disable comparison instead of returning invented zero distances',()=>{
  const c=operationsCatalog({withLocations:true});
  c.passengers[0].fictionalLocation={xKm:NaN,yKm:2};
  const geometry=d.geometryForCatalog(c,'geo-v1');
  const routes=operationRequest(c,'2026-12-07','morning','geo-v1','unit-test').routes;
  assert.equal(d.distanceHint(routes,c,geometry),null);
  assert.equal(d.compareDistance(routes,routes,geometry),null);
});
test('comparison keeps unchanged/worse cases and never repeats unverified AI savings claims',()=>{
  const c=operationsCatalog({withLocations:true}),g=d.geometryForCatalog(c,'geo-v1');
  const routes=operationRequest(c,'2026-12-07','morning','geo-v1','unit-test').routes;
  const hint=d.distanceHint(routes,c,g);
  const unchanged=d.compareDistance(routes,routes,g);
  const worse=d.compareDistance(hint.routes,routes,g);
  assert.equal(unchanged.beforeKm,unchanged.afterKm);
  assert.ok(d.measuredReasons(unchanged)[0].includes('개선이 확인되지'));
  assert.ok(worse.afterKm>worse.beforeKm);
  assert.ok(d.measuredReasons(worse)[0].includes('증가'));
});
test('already minimal single-passenger course is not changed just to create a proposal',()=>{
  const geometry={center:{xKm:0,yKm:0},locations:new Map([['a',{xKm:1,yKm:0}]])};
  const routes=[{baseRouteId:'r',vehicleId:'v',passengerIds:['a']}];
  const hint=d.distanceHint(routes,{vehicles:[{id:'v',passengerCapacity:1}]},geometry);
  assert.deepEqual(hint.routes,[{baseRouteId:'r',passengerIds:['a']}]);assert.equal(hint.estimatedTotalKm,2);
});
test('small global savings cannot justify a move from 3/5 passengers to 2/6',()=>{
  const score=d.reassignmentGain(100,98.76,3**2+5**2,2**2+6**2);
  assert.equal(score.penaltyKm,1.5);assert.equal(score.allowed,false);
  assert.ok(score.netGainKm<0);
  assert.equal(d.reassignmentGain(100,96.6,34,40).allowed,false);
  assert.equal(d.reassignmentGain(100,95,34,40).allowed,true);
});
test('both absolute and percentage thresholds apply to savings beyond within-course ordering',()=>{
  assert.equal(d.reassignmentGain(10,9.7,8,8).allowed,false);
  assert.equal(d.reassignmentGain(100,99,8,8).allowed,false);
  assert.equal(d.reassignmentGain(100,98,8,8).allowed,true);
  // Even a gain over the original 100km is insufficient if order-only yields 80km.
  assert.equal(d.reassignmentGain(80,90,8,8).allowed,false);
  assert.equal(d.reassignmentGain(null,null,8,8).allowed,false);
});
function smallScenario() {
  const before=[{baseRouteId:'a',staffId:'s1',vehicleId:'va',passengerIds:['a','b']},
    {baseRouteId:'b',staffId:'s2',vehicleId:'vb',passengerIds:['c','e']}];
  const after=[{...before[0],passengerIds:['a']},{...before[1],passengerIds:['c','b','e']}];
  const catalog={vehicles:[{id:'va',passengerCapacity:2},{id:'vb',passengerCapacity:3}]};
  const geometry={center:{xKm:0,yKm:0},locations:new Map([
    ['a',{xKm:1,yKm:0}],['b',{xKm:100,yKm:0}],['c',{xKm:99,yKm:0}],['e',{xKm:101,yKm:0}],
  ])};
  return {before,after,catalog,geometry};
}
test('a genuinely large additional saving may outweigh an imbalance penalty',()=>{
  const {before,after,catalog,geometry}=smallScenario();
  const result=d.evaluateReassignment(before,after,catalog,geometry);
  assert.equal(result.allowed,true);assert.equal(result.movedPassengers,1);
  assert.equal(result.penaltyKm,0.5);assert.ok(result.netGainKm>result.requiredKm);
});
test('a necessary absent-staff handoff is allowed, but does not authorize arbitrary passenger movement',()=>{
  const {before,after,catalog,geometry}=smallScenario();
  const noCoordinates={...geometry,locations:new Map()};
  const handoff=before.map((r,i)=>({...r,staffId:i===0?'s3':r.staffId}));
  assert.equal(d.evaluateReassignment(before,handoff,catalog,noCoordinates,['s1']).allowed,true);
  const unnecessary=after.map((r,i)=>({...r,staffId:i===0?'s3':r.staffId}));
  assert.equal(d.evaluateReassignment(before,unnecessary,catalog,noCoordinates,['s1']).allowed,false);
  assert.equal(d.evaluateReassignment(before,handoff,catalog,geometry).reason,'UNNECESSARY_STAFF_CHANGE');
});
test('a real capacity repair can take precedence; initial/final business validation remains separate',()=>{
  const {before,after,catalog,geometry}=smallScenario();
  const overloaded=[{...before[0],passengerIds:['a','b','c']},{...before[1],passengerIds:['e']}];
  const repaired=[{...after[0],passengerIds:['a','b']},{...after[1],passengerIds:['c','e']}];
  const result=d.evaluateReassignment(overloaded,repaired,catalog,{...geometry,locations:new Map()});
  assert.equal(result.allowed,true);assert.equal(result.reason,'ASSIGNMENT_REPAIR');
});
test('routine 20/80 heuristic now keeps passenger membership rather than spending small savings on relocations',()=>{
  const c=operationsCatalog({withLocations:true});
  const routes=operationRequest(c,'2026-12-07','morning','geo-v1','unit-test').routes;
  const geometry=d.geometryForCatalog(c,'geo-v1'),hint=d.distanceHint(routes,c,geometry);
  for(const route of hint.routes)assert.deepEqual([...route.passengerIds].sort(),[...routes.find(r=>r.baseRouteId===route.baseRouteId).passengerIds].sort());
  const candidate=hint.routes.map(r=>({...routes.find(old=>old.baseRouteId===r.baseRouteId),passengerIds:r.passengerIds}));
  assert.equal(d.evaluateReassignment(routes,candidate,c,geometry).reason,'KEEP_COURSES');
  assert.ok(hint.estimatedTotalKm<d.totalDistance(routes,geometry));
});
