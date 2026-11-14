'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {operationsCatalog,operationRequest}=require('../../tools/operations_fixture.cjs');
const {assembleSuggestion,suggestionFailureSummary}=require('../suggestion-service');
const {validateSchedule,safeViolation}=require('../validation');
const catalog=operationsCatalog();
function fixture() {
  const input=operationRequest(catalog,'2026-12-07','morning','test-v1','unit-test');
  const answer={routes:input.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:[...r.passengerIds]})),reasons:['고정 테스트']};
  return {input,answer,absent:[]};
}
for(const [name,violation,mutate] of [
  ['missing course','ROUTE_MISSING',f=>f.answer.routes.pop()],
  ['only changed course returned','ROUTE_MISSING',f=>f.answer.routes=f.answer.routes.slice(0,1)],
  ['duplicate course','ROUTE_DUPLICATE',f=>f.answer.routes[1].baseRouteId=f.answer.routes[0].baseRouteId],
  ['unknown course','ROUTE_UNKNOWN',f=>f.answer.routes[0].baseRouteId='unknown'],
  ['missing passenger','PASSENGER_MISSING',f=>f.answer.routes[0].passengerIds.pop()],
  ['passenger repeated within route','PASSENGER_DUPLICATE',f=>f.answer.routes[0].passengerIds.push('p1')],
  ['passenger repeated across routes','PASSENGER_DUPLICATE',f=>f.answer.routes[1].passengerIds.push('p1')],
  ['unknown passenger','PASSENGER_UNKNOWN',f=>f.answer.routes[0].passengerIds[0]='unknown'],
  ['duplicate employee','STAFF_DUPLICATE',f=>f.answer.routes[0].staffId='s2'],
  ['absent employee','STAFF_ABSENT',f=>f.absent=['s1']],
  ['weekly day off','STAFF_UNAVAILABLE',f=>{f.input.date='2026-11-13';f.answer.routes[0].staffId='s3';}],
  ['unknown employee','STAFF_UNAVAILABLE',f=>f.answer.routes[0].staffId='unknown'],
  ['fixed vehicle capacity exceeded','VEHICLE_CAPACITY_EXCEEDED',f=>{
    f.answer.routes[0].passengerIds=['p3'];f.answer.routes[1].passengerIds.push('p1','p2');
  }],
  ['absent passenger restored by AI','REMOVED_PASSENGER_ASSIGNED',f=>{
    f.input.absentIds=['p2'];f.input.routes[0].passengerIds=['p1','p3'];delete f.input.routes[0].estimatedVisitMinutes.p2;
  }],
  ['forbidden route property','RESPONSE_FIELDS_FORBIDDEN',f=>f.answer.routes[0].vehicleId='v2'],
  ['forbidden response property','RESPONSE_FIELDS_FORBIDDEN',f=>f.answer.absentIds=[]],
  ['invalid reasons','REASONS_INVALID',f=>f.answer.reasons=Array(31).fill('reason')],
])test(`suggestion diagnostics: ${name}`,()=>{
  const f=fixture();mutate(f);
  const before=JSON.stringify(f.input);
  assert.throws(()=>assembleSuggestion(f.input,f.answer,catalog,f.absent),e=>{
    assert.equal(e.code,'invalid-argument');assert.equal(safeViolation(e),violation);return true;
  });
  assert.equal(JSON.stringify(f.input),before);
});
test('valid 20/80 proposal preserves every rule and manual time without requiring a separate time review',()=>{
  const {input,answer}=fixture();
  answer.routes[0].passengerIds.reverse();
  const result=assembleSuggestion(input,answer,catalog,[]);
  assert.equal(result.routes.length,19);
  assert.equal(new Set(result.routes.flatMap(r=>r.passengerIds)).size,80);
  assert.deepEqual(result.routes[0].estimatedVisitMinutes,input.routes[0].estimatedVisitMinutes);
  assert.equal(result.routes[0].vehicleId,input.routes[0].vehicleId);
  assert.ok(result.warnings.length>0);
  assert.doesNotThrow(()=>validateSchedule({...input,routes:result.routes},catalog));
});
test('shared validator distinguishes vehicle duplication without changing its rejection',()=>{
  const {input}=fixture();input.routes[1].vehicleId='v1';
  assert.throws(()=>validateSchedule(input,catalog),e=>safeViolation(e)==='VEHICLE_DUPLICATE');
});
test('failure summaries expose only allowlisted violations and aggregate counts, never IDs, reasons or raw errors',()=>{
  const {input,answer}=fixture();
  answer.reasons=['never-log-private-response'];answer.routes.pop();
  const error={details:{violation:'ROUTE_MISSING',private:'never-log-private-details'},message:'never-log-private-error',stack:'never-log-private-stack'};
  const summary=suggestionFailureSummary(input,answer,error,18);
  assert.deepEqual(summary,{violationType:'ROUTE_MISSING',expectedRouteCount:19,returnedRouteCount:18,
    expectedPassengerCount:80,returnedPassengerCount:76,availableStaffCount:18,insufficientAvailableStaff:true});
  assert.ok(!JSON.stringify(summary).includes('never-log'));
  assert.equal(safeViolation({details:{violation:'never-log-code'}}),undefined);
  assert.equal(suggestionFailureSummary(input,null,{details:{violation:'never-log-code'}},19).violationType,'UNCLASSIFIED_VALIDATION');
});
test('Friday absence can leave only 18 available staff for 19 fixed courses; prompt changes cannot make that feasible',()=>{
  const {input,answer}=fixture();input.date='2026-11-13';
  const available=catalog.staff.filter(s=>s.active&&!s.unavailableWeekdays.includes(5)&&s.id!=='s1');
  assert.equal(available.length,18);
  let failure;try{assembleSuggestion(input,answer,catalog,['s1']);}catch(error){failure=error;}
  assert.equal(safeViolation(failure),'STAFF_ABSENT');
  assert.equal(suggestionFailureSummary(input,answer,failure,available.length).insufficientAvailableStaff,true);
});
