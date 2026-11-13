'use strict';
const {HttpsError}=require('firebase-functions/v2/https');
const {validateRequest,validateSchedule,safeViolation}=require('./validation');
const {absenceData}=require('./staff-absence-service');
const {validateExistingSchedule}=require('./existing-schedule');
const {geometryForCatalog,distanceHint,compareDistance,measuredReasons,evaluateReassignment,REASSIGNMENT_POLICY,orderOnlyRoutes,totalDistance}=require('./schedule-distance');

function guardSuggestionEnvironment(db,env=process.env) {
  if(env.FUNCTIONS_EMULATOR!=='true'||env.GCLOUD_PROJECT!=='demo-senior-transport'||
    !/^demo-/.test(db.projectId)||
    !['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST'].every(key=>/^(127\.0\.0\.1|localhost):\d+$/.test(env[key]||''))) {
    throw new HttpsError('failed-precondition','AI 시연은 demo Firebase Emulator에서만 사용할 수 있습니다.');
  }
}
function structural(data) {
  return {...data,routes:data.routes.map(r=>({...r,estimatedVisitMinutes:{},estimatedVisitSources:{}}))};
}
function validateEstimates(data) {
  for(const r of data.routes) {
    const times=r.estimatedVisitMinutes,sources=r.estimatedVisitSources;
    if(!times||typeof times!=='object'||Array.isArray(times)||Object.entries(times).some(([id,t])=>
      !r.passengerIds.includes(id)||!Number.isInteger(t)||t<0||t>=1440)||
      (sources!==undefined&&(!sources||typeof sources!=='object'||Array.isArray(sources)||Object.entries(sources).some(([id,s])=>
        !Object.hasOwn(times,id)||!['manual','fixedInterval'].includes(s))))) {
      throw new HttpsError('invalid-argument','초안의 예상 시각·출처 형식을 확인해 주세요.');
    }
  }
}
async function readContext(db,uid,input) {
  return db.runTransaction(async tx=>{
    const [profile,schedule,settings,metadata]=await tx.getAll(db.doc(`users/${uid}`),
      db.doc(`schedules/${input.date}_${input.period}`),db.doc('settings/schedules'),db.doc(`catalogs/${input.catalogVersion}`));
    if(profile.data()?.active!==true||profile.data()?.role!=='admin') throw new HttpsError('permission-denied','관리자만 AI 추천을 요청할 수 있습니다.');
    const old=schedule.data();
    if(schedule.exists)validateExistingSchedule(old,input.date,input.period);
    if((old?.version??0)!==input.expectedVersion)throw new HttpsError('aborted','확정 일정이 변경되었습니다. 최신본을 확인해 주세요.');
    if((old?.catalogVersion||settings.data()?.catalogVersion)!==input.catalogVersion||metadata.data()?.ready!==true||metadata.data()?.fictional!==true) {
      throw new HttpsError('failed-precondition','등록된 가상 기본 데이터 버전을 확인해 주세요.');
    }
    const catalog={};
    for(const name of ['staff','vehicles','passengers','baseRoutes']) {
      catalog[name]=(await tx.get(db.collection(`catalogs/${input.catalogVersion}/${name}`))).docs.map(d=>({...d.data(),id:d.id}));
    }
    const records=await tx.get(db.collection(`staffAvailability/${input.date}/staff`));
    const versions={},absentStaffIds=[];
    for(const s of catalog.staff) {
      const document=records.docs.find(d=>d.id===s.id)||{exists:false};
      const status=absenceData(document,input.date,s.id);
      versions[s.id]=status.version;
      if(status.unavailablePeriods.includes(input.period))absentStaffIds.push(s.id);
    }
    const expected=input.expectedAvailabilityVersions;
    if(!expected||Object.keys(expected).length!==catalog.staff.length||catalog.staff.some(s=>expected[s.id]!==versions[s.id])) {
      throw new HttpsError('aborted','결근 상태가 변경되었습니다. 최신 상태로 다시 요청해 주세요.');
    }
    return {catalog,versions,absentStaffIds};
  });
}
function assembleSuggestion(input,answer,catalog,absentStaffIds) {
  const invalid=violation=>{throw new HttpsError('invalid-argument','AI 추천안이 업무 규칙을 충족하지 않습니다. 기존 일정은 유지됩니다.',{violation});};
  if(!answer||typeof answer!=='object'||Array.isArray(answer)||!Array.isArray(answer.routes))invalid('RESPONSE_FORMAT_INVALID');
  if(Object.keys(answer).some(k=>!['routes','reasons'].includes(k)))invalid('RESPONSE_FIELDS_FORBIDDEN');
  if(answer.routes.length!==input.routes.length)invalid(answer.routes.length<input.routes.length?'ROUTE_MISSING':'ROUTE_COUNT_MISMATCH');
  if(!Array.isArray(answer.reasons)||answer.reasons.length>30||answer.reasons.some(r=>typeof r!=='string'||r.length>2000))invalid('REASONS_INVALID');
  const estimates=new Map();
  for(const r of input.routes)for(const id of r.passengerIds)estimates.set(id,{time:r.estimatedVisitMinutes[id],source:r.estimatedVisitSources?.[id]});
  const byId=new Map();
  for(const r of answer.routes) {
    if(!r||typeof r!=='object'||Array.isArray(r)||!Array.isArray(r.passengerIds))invalid('RESPONSE_FORMAT_INVALID');
    if(Object.keys(r).some(k=>!['baseRouteId','staffId','passengerIds'].includes(k)))invalid('RESPONSE_FIELDS_FORBIDDEN');
    if(!input.routes.some(old=>old.baseRouteId===r.baseRouteId))invalid('ROUTE_UNKNOWN');
    if(byId.has(r.baseRouteId))invalid('ROUTE_DUPLICATE');
    byId.set(r.baseRouteId,r);
  }
  const routes=input.routes.map(old=>{
    const proposed=byId.get(old.baseRouteId);if(!proposed)invalid('ROUTE_MISSING');
    return {...old,staffId:proposed.staffId,passengerIds:proposed.passengerIds,
      estimatedVisitMinutes:Object.fromEntries(proposed.passengerIds.filter(id=>estimates.get(id)?.time!==undefined).map(id=>[id,estimates.get(id).time])),
      estimatedVisitSources:Object.fromEntries(proposed.passengerIds.filter(id=>estimates.get(id)?.time!==undefined&&estimates.get(id)?.source!==undefined).map(id=>[id,estimates.get(id).source])),
    };
  });
  const candidate={...input,routes};
  validateSchedule(structural(candidate),catalog);
  if(routes.some(r=>absentStaffIds.includes(r.staffId)))invalid('STAFF_ABSENT');
  const warnings=[];
  for(const r of routes) {
    try{validateSchedule({...structural(candidate),routes:routes.map(other=>other===r?r:{...other,estimatedVisitMinutes:{},estimatedVisitSources:{}})},catalog);}
    catch{warnings.push(`${catalog.baseRoutes.find(b=>b.id===r.baseRouteId).name}: 방문 순서와 기존 예상 시각을 재검토해 주세요.`);}
  }
  return {routes,reasons:answer.reasons,warnings};
}
function suggestionFailureSummary(input,answer,error,availableStaffCount) {
  const returned=Array.isArray(answer?.routes)?answer.routes:null;
  return {violationType:safeViolation(error)||'UNCLASSIFIED_VALIDATION',
    expectedRouteCount:input.routes.length,returnedRouteCount:returned?.length??null,
    expectedPassengerCount:new Set(input.routes.flatMap(r=>r.passengerIds)).size,
    returnedPassengerCount:returned?.every(r=>Array.isArray(r?.passengerIds))?returned.reduce((sum,r)=>sum+r.passengerIds.length,0):null,
    availableStaffCount,insufficientAvailableStaff:availableStaffCount<input.routes.length};
}
async function suggest(db,uid,input,{generate,env=process.env,onStage=()=>{},onValidationFailure=()=>{}}={}) {
  onStage('validate-request');
  guardSuggestionEnvironment(db,env);
  if(!uid)throw new HttpsError('unauthenticated','로그인이 필요합니다.');
  validateRequest(input);
  onStage('read-context');
  const initial=await readContext(db,uid,input);
  // The incoming draft may still contain an absent/off-duty owner. Allow the
  // AI to replace that owner, but do not allow malformed routes or lost people.
  onStage('validate-draft');
  validateSchedule(structural(input),{...initial.catalog,staff:initial.catalog.staff.map(s=>({...s,active:true,unavailableWeekdays:[]}))});
  validateEstimates(input);
  const weekday=new Date(`${input.date}T00:00:00Z`).getUTCDay()||7;
  const allowedStaffIds=initial.catalog.staff.filter(s=>s.active===true&&!(s.unavailableWeekdays||[]).includes(weekday)&&!initial.absentStaffIds.includes(s.id)).map(s=>s.id);
  const removed=new Set([...input.absentIds,...input.excludedIds]);
  const requiredPassengerIds=[...new Set(initial.catalog.baseRoutes.filter(r=>r.period===input.period).flatMap(r=>r.passengerIds))].filter(id=>!removed.has(id));
  const geometry=geometryForCatalog(initial.catalog,input.catalogVersion);
  const hint=distanceHint(input.routes,initial.catalog,geometry);
  const unavailableStaffIds=initial.catalog.staff.filter(s=>!allowedStaffIds.includes(s.id)).map(s=>s.id);
  onStage('gemini-generate');
  const answer=await generate({date:input.date,period:input.period,availableStaffIds:allowedStaffIds,
    requiredPassengerIds,requiredRouteCount:input.routes.length,
    reassignmentPolicy:REASSIGNMENT_POLICY,
    ...(hint?{locationModel:{method:hint.method,center:geometry.center,
      passengers:requiredPassengerIds.map(id=>({id,...geometry.locations.get(id)})),
      currentTotalKm:compareDistance(input.routes,input.routes,geometry).beforeKm,
      orderOnlyTotalKm:totalDistance(orderOnlyRoutes(input.routes,geometry),geometry),heuristicCandidate:hint}}:{}),
    absentIds:input.absentIds,excludedIds:input.excludedIds,
    vehicles:initial.catalog.vehicles.map(v=>({id:v.id,passengerCapacity:v.passengerCapacity})),
    baseRoutes:initial.catalog.baseRoutes.filter(r=>r.period===input.period).map(r=>({id:r.id,passengerIds:r.passengerIds})),
    routes:input.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,vehicleId:r.vehicleId,
      passengerCapacity:initial.catalog.vehicles.find(v=>v.id===r.vehicleId).passengerCapacity,passengerIds:r.passengerIds})),
  });
  onStage('validate-suggestion');
  let result;
  let assessment;
  try {
    result=assembleSuggestion(input,answer,initial.catalog,initial.absentStaffIds);
    assessment=evaluateReassignment(input.routes,result.routes,initial.catalog,geometry,unavailableStaffIds);
    if(!assessment.allowed)throw new HttpsError('invalid-argument','이용자의 기존 코스를 유지해 다시 제안해 주세요.',{violation:'REASSIGNMENT_NOT_JUSTIFIED'});
  }
  catch(error) {
    onValidationFailure(suggestionFailureSummary(input,answer,error,allowedStaffIds.length));
    throw error;
  }
  onStage('recheck-context');
  const latest=await readContext(db,uid,input);
  if(JSON.stringify(initial)!==JSON.stringify(latest))throw new HttpsError('aborted','추천 중 기본 데이터나 결근 상태가 변경되었습니다. 다시 요청해 주세요.');
  const distanceComparison=compareDistance(input.routes,result.routes,geometry);
  // Unverified LLM distance claims must not contradict measured results in UI.
  return {...result,...(distanceComparison?{distanceComparison,reasons:[...measuredReasons(distanceComparison),
    assessment.reason==='KEEP_COURSES'?'이용자의 기존 코스는 유지했습니다. 방문 순서와 필요한 담당 직원 변경만 검토했습니다.':
    assessment.reason==='ASSIGNMENT_REPAIR'?'배정 문제를 해결하기 위해 필요한 이용자 이동을 검토했습니다.':
    '코스를 옮기는 부담과 이용자 수 차이를 고려해도 거리 이득이 충분한 변경입니다.']}:{ }),
    routes:result.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:r.passengerIds})),
    date:input.date,period:input.period,catalogVersion:input.catalogVersion,expectedVersion:input.expectedVersion};
}
module.exports={suggest,assembleSuggestion,guardSuggestionEnvironment,suggestionFailureSummary};
