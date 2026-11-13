'use strict';
// Fictional Cartesian coordinates in km, not latitude/longitude or addresses.
const METHOD='fictional-euclidean-round-trip-v1';
const CENTER=Object.freeze({xKm:0,yKm:0});
const EPSILON_KM=0.001;
const REASSIGNMENT_POLICY=Object.freeze({minAdditionalKm:1,minAdditionalFraction:0.02,imbalancePenaltyKmPerPoint:0.25});
const workload=routes=>routes.reduce((sum,r)=>sum+r.passengerIds.length**2,0);
function orderOnlyRoutes(routes,geometry) {
  if(totalDistance(routes,geometry)===null)return null;
  return routes.map(r=>({...r,passengerIds:nearestOrder(r.passengerIds,geometry)}));
}
function reassignmentGain(referenceKm,afterKm,beforeWorkload,afterWorkload) {
  const penaltyKm=Math.max(0,afterWorkload-beforeWorkload)*REASSIGNMENT_POLICY.imbalancePenaltyKmPerPoint;
  if(referenceKm===null||afterKm===null)return {allowed:false,penaltyKm,reason:'DISTANCE_UNAVAILABLE'};
  const netGainKm=referenceKm-afterKm-penaltyKm;
  const requiredKm=Math.max(REASSIGNMENT_POLICY.minAdditionalKm,referenceKm*REASSIGNMENT_POLICY.minAdditionalFraction);
  return {allowed:netGainKm>=requiredKm-1e-9,netGainKm,requiredKm,penaltyKm,reason:'DISTANCE_AND_WORKLOAD'};
}
function evaluateReassignment(before,after,catalog,geometry,unavailableStaffIds=[]) {
  const oldById=new Map(before.map(r=>[r.baseRouteId,r]));
  if(after.some(r=>r.staffId!==oldById.get(r.baseRouteId).staffId&&!unavailableStaffIds.includes(oldById.get(r.baseRouteId).staffId))) {
    return {allowed:false,reason:'UNNECESSARY_STAFF_CHANGE',movedPassengers:0};
  }
  const owners=new Map(before.flatMap(r=>r.passengerIds.map(id=>[id,r.baseRouteId])));
  const moves=after.flatMap(r=>r.passengerIds.filter(id=>owners.get(id)!==r.baseRouteId).map(id=>({from:owners.get(id),to:r.baseRouteId})));
  if(!moves.length)return {allowed:true,reason:'KEEP_COURSES',movedPassengers:0};
  // Evaluate membership changes independently of a necessary staff handoff.
  // An absent owner alone must not justify unrelated passenger moves.
  const counterfactual=before.map(r=>({...r,staffId:after.find(a=>a.baseRouteId===r.baseRouteId).staffId}));
  const excess=r=>Math.max(0,r.passengerIds.length-catalog.vehicles.find(v=>v.id===r.vehicleId).passengerCapacity);
  const problemRoutes=new Set(counterfactual.filter(r=>excess(r)>0).map(r=>r.baseRouteId));
  const repair=counterfactual.reduce((sum,r)=>sum+excess(r),0)>after.reduce((sum,r)=>sum+excess(r),0)&&
    moves.every(m=>problemRoutes.has(m.from)||problemRoutes.has(m.to));
  if(repair)return {allowed:true,reason:'ASSIGNMENT_REPAIR',movedPassengers:moves.length};
  const ordered=orderOnlyRoutes(before,geometry);
  const assessment=reassignmentGain(ordered?totalDistance(ordered,geometry):null,totalDistance(after,geometry),workload(before),workload(after));
  return {...assessment,movedPassengers:moves.length};
}
function withFictionalLocations(catalog) {
  const positions=new Map();
  const offsets=[[0.05,0.02],[0.75,0.75],[0.10,0.12],[0.80,0.08],[0.12,0.68],[0.50,0.35]];
  catalog.baseRoutes.filter(r=>r.period==='morning')
    .sort((a,b)=>a.id.localeCompare(b.id,'en',{numeric:true})).forEach((route,group)=>{
    route.passengerIds.forEach((id,index)=>{
      const [dx,dy]=offsets[index%offsets.length];
      positions.set(id,{xKm:1+(group%5)*1.6+dx,yKm:1+Math.floor(group/5)*1.6+dy});
    });
  });
  return {...catalog,passengers:catalog.passengers.map(p=>({...p,
    ...(positions.has(p.id)?{fictionalLocation:positions.get(p.id)}:{}),
  }))};
}
function geometryForCatalog(catalog,version) {
  // Compatibility overlay only for the known 20/80 fictional Emulator fixture.
  // Never invent positions for arbitrary catalogs or geocode an address.
  let source=catalog;
  if(version==='operations-20x80-v1'&&catalog.passengers.length===80&&
    catalog.passengers.every(p=>/^p(?:[1-9]|[1-7]\d|80)$/.test(p.id))&&
    catalog.passengers.every(p=>p.fictionalLocation===undefined))source=withFictionalLocations(catalog);
  const locations=new Map();
  for(const p of source.passengers) {
    const point=p.fictionalLocation;
    if(point&&Number.isFinite(point.xKm)&&Number.isFinite(point.yKm)&&
      Math.abs(point.xKm)<=100&&Math.abs(point.yKm)<=100)locations.set(p.id,{xKm:point.xKm,yKm:point.yKm});
  }
  return {center:CENTER,locations};
}
const distance=(a,b)=>Math.hypot(a.xKm-b.xKm,a.yKm-b.yKm);
function routeDistance(ids,geometry) {
  let last=geometry.center,total=0;
  for(const id of ids) {
    const point=geometry.locations.get(id);
    if(!point)return null;
    total+=distance(last,point);last=point;
  }
  return total+distance(last,geometry.center);
}
function totalDistance(routes,geometry) {
  let total=0;
  for(const route of routes) {
    const km=routeDistance(route.passengerIds,geometry);
    if(km===null)return null;
    total+=km;
  }
  return total;
}
function nearestOrder(ids,geometry) {
  const remaining=[...ids],ordered=[];
  let last=geometry.center;
  while(remaining.length) {
    let nearest=0;
    for(let i=1;i<remaining.length;i++)if(distance(last,geometry.locations.get(remaining[i]))<distance(last,geometry.locations.get(remaining[nearest])))nearest=i;
    const [id]=remaining.splice(nearest,1);ordered.push(id);last=geometry.locations.get(id);
  }
  return routeDistance(ordered,geometry)<routeDistance(ids,geometry)-EPSILON_KM?ordered:[...ids];
}
function distanceHint(routes,catalog,geometry) {
  if(totalDistance(routes,geometry)===null)return null;
  const hint=routes.map(r=>({baseRouteId:r.baseRouteId,passengerIds:[...r.passengerIds]}));
  // Keep most baseline courses intact: take only the best single-course order
  // improvement, then allow a relocation affecting at most two courses total.
  let bestOrder=null,bestOrderDelta=-EPSILON_KM;
  routes.forEach((r,index)=>{
    const order=nearestOrder(r.passengerIds,geometry);
    const delta=routeDistance(order,geometry)-routeDistance(r.passengerIds,geometry);
    if(delta<bestOrderDelta){bestOrderDelta=delta;bestOrder={index,order};}
  });
  if(bestOrder)hint[bestOrder.index].passengerIds=bestOrder.order;
  const capacities=routes.map(r=>catalog.vehicles.find(v=>v.id===r.vehicleId).passengerCapacity);
  const referenceKm=totalDistance(orderOnlyRoutes(routes,geometry),geometry);
  const hintKm=totalDistance(hint,geometry),originalWorkload=workload(routes);
  // One bounded best-improving relocation, checking all insertion positions.
  // Staff, vehicles, course IDs, absences and estimates are never modified.
  let best=null,bestDelta=-EPSILON_KM;
  for(let from=0;from<hint.length;from++)for(let to=0;to<hint.length;to++) {
    if(from===to||hint[to].passengerIds.length>=capacities[to])continue;
    if(bestOrder&&new Set([bestOrder.index,from,to]).size>2)continue;
    const source=hint[from].passengerIds,target=hint[to].passengerIds;
    const old=routeDistance(source,geometry)+routeDistance(target,geometry);
    for(const id of source)for(let at=0;at<=target.length;at++) {
      const nextSource=source.filter(p=>p!==id),nextTarget=[...target];nextTarget.splice(at,0,id);
      const delta=routeDistance(nextSource,geometry)+routeDistance(nextTarget,geometry)-old;
      const changedWorkload=originalWorkload-source.length**2-target.length**2+nextSource.length**2+nextTarget.length**2;
      const gain=reassignmentGain(referenceKm,hintKm+delta,originalWorkload,changedWorkload);
      const weightedDelta=delta+gain.penaltyKm;
      if(gain.allowed&&weightedDelta<bestDelta){bestDelta=weightedDelta;best={from,to,nextSource,nextTarget};}
    }
  }
  if(best){hint[best.from].passengerIds=best.nextSource;hint[best.to].passengerIds=best.nextTarget;}
  return {method:METHOD,estimatedTotalKm:totalDistance(hint,geometry),routes:hint};
}
function compareDistance(before,after,geometry) {
  const beforeKm=totalDistance(before,geometry),afterKm=totalDistance(after,geometry);
  return beforeKm===null||afterKm===null?null:{method:METHOD,beforeKm,afterKm};
}
function measuredReasons(comparison) {
  const delta=comparison.beforeKm-comparison.afterKm;
  if(delta>EPSILON_KM)return ['프로그램의 동일한 가상 좌표·센터 왕복 직선 거리 계산에서 추정 총 이동 거리가 감소했습니다. 실제 도로 이동 거리나 운행 시간 개선을 보장하지 않습니다.'];
  if(delta< -EPSILON_KM)return ['프로그램 계산에서 추정 총 이동 거리가 증가했습니다. 거리 개선안으로 볼 수 없으며, 필요한 직원 배정 변경 등이 있는지 별도로 검토해 주세요.'];
  return ['프로그램 계산에서 추정 총 이동 거리 개선이 확인되지 않았습니다. 배정이 동일하면 변경하지 않아도 됩니다.'];
}
module.exports={METHOD,EPSILON_KM,REASSIGNMENT_POLICY,withFictionalLocations,geometryForCatalog,routeDistance,totalDistance,distanceHint,compareDistance,measuredReasons,evaluateReassignment,reassignmentGain,orderOnlyRoutes};
