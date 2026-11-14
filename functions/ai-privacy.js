'use strict';
const {randomBytes} = require('node:crypto');
const {HttpsError} = require('firebase-functions/v2/https');

// Rebuild the outbound object. Never recursively forward catalog/input fields.
function anonymize(input) {
  const maps = {}, reverse = {}, permitted = new Set();
  const prefix = randomBytes(12).toString('hex');
  for (const type of ['staff','route','passenger','vehicle']) {
    maps[type] = new Map(); reverse[type] = new Map();
  }
  const alias = (type,id) => {
    if (typeof id !== 'string') throw new HttpsError('invalid-argument','추천 입력을 확인해 주세요.');
    if (!maps[type].has(id)) {
      const value = `${type}_${prefix}_${maps[type].size}`;
      maps[type].set(id,value); reverse[type].set(value,id); permitted.add(value);
    }
    return maps[type].get(id);
  };
  const list = (type,ids) => ids.map(id=>alias(type,id));
  const route = r => ({baseRouteId:alias('route',r.baseRouteId),
    passengerIds:list('passenger',r.passengerIds)});
  const output = {
    weekday:new Date(`${input.date}T00:00:00Z`).getUTCDay()||7,
    period:input.period,availableStaffIds:list('staff',input.availableStaffIds),
    requiredPassengerIds:list('passenger',input.requiredPassengerIds),requiredRouteCount:input.requiredRouteCount,
    absentIds:list('passenger',input.absentIds),excludedIds:list('passenger',input.excludedIds),
    vehicles:input.vehicles.map(v=>({id:alias('vehicle',v.id),passengerCapacity:v.passengerCapacity})),
    baseRoutes:input.baseRoutes.map(r=>({id:alias('route',r.id),passengerIds:list('passenger',r.passengerIds)})),
    routes:input.routes.map(r=>({...route(r),staffId:alias('staff',r.staffId),
      vehicleId:alias('vehicle',r.vehicleId),passengerCapacity:r.passengerCapacity})),
    reassignmentPolicy:{minAdditionalKm:input.reassignmentPolicy.minAdditionalKm,
      minAdditionalFraction:input.reassignmentPolicy.minAdditionalFraction,
      imbalancePenaltyKmPerPoint:input.reassignmentPolicy.imbalancePenaltyKmPerPoint},
  };
  if(input.locationModel) {
    const m=input.locationModel;
    const point=p=>({xKm:p.xKm,yKm:p.yKm});
    output.locationModel={method:'fictional-planar-km-center-roundtrip',center:point(m.center),
      passengers:m.passengers.map(p=>({id:alias('passenger',p.id),...point(p)})),
      currentTotalKm:m.currentTotalKm,orderOnlyTotalKm:m.orderOnlyTotalKm,
      heuristicCandidate:{method:'fictional-planar-km-center-roundtrip',estimatedTotalKm:m.heuristicCandidate.estimatedTotalKm,
        routes:m.heuristicCandidate.routes.map(route)}};
  }
  const literals=new Set(['morning','afternoon','fictional-planar-km-center-roundtrip']);
  const originals=new Set(Object.values(maps).flatMap(map=>[...map.keys()]));
  function inspect(value) {
    if(typeof value==='string'&&originals.has(value))throw new Error('UNSAFE_AI_INPUT');
    if(typeof value==='string'&&!permitted.has(value)&&!literals.has(value))throw new Error('UNSAFE_AI_INPUT');
    if(typeof value==='number'&&!Number.isFinite(value))throw new Error('UNSAFE_AI_INPUT');
    if(value===undefined||value===null)throw new Error('UNSAFE_AI_INPUT');
    if(value&&typeof value==='object')Object.values(value).forEach(inspect);
  }
  inspect(output);
  return {input:output,restore(answer) {
    const decode=(type,value)=>{
      if(!reverse[type].has(value))throw new HttpsError('invalid-argument','AI 추천에 허용되지 않은 식별자가 있습니다.');
      return reverse[type].get(value);
    };
    if(!answer||!Array.isArray(answer.routes)||Object.keys(answer).some(k=>!['routes','reasons'].includes(k))) {
      throw new HttpsError('invalid-argument','AI 응답 형식을 확인해 주세요.');
    }
    return {routes:answer.routes.map(r=>{
      if(!r||Object.keys(r).some(k=>!['baseRouteId','staffId','passengerIds'].includes(k))||!Array.isArray(r.passengerIds)) {
        throw new HttpsError('invalid-argument','AI 응답 필드를 확인해 주세요.');
      }
      return {baseRouteId:decode('route',r.baseRouteId),staffId:decode('staff',r.staffId),
        passengerIds:r.passengerIds.map(id=>decode('passenger',id))};
    }),reasons:['비식별 가상 데이터를 이용한 추천입니다. 변경 내용을 확인해 주세요.']};
  }};
}
module.exports={anonymize};
