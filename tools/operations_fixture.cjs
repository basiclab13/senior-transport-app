'use strict';
const {fictionalCatalog} = require('./fictional_catalog.cjs');

// Emulator-only operational scale. Existing baseline IDs, routes and order survive.
function operationsCatalog() {
  const catalog = fictionalCatalog(false);
  let passengerNumber = 6;
  for (let i=4;i<=20;i++) {
    catalog.staff.push({id:`s${i}`,name:`가상 직원 ${i}`,active:true,unavailableWeekdays:[]});
    catalog.vehicles.push({id:`v${i}`,name:`가상 차량 ${i}`,passengerCapacity:6});
    const ids=[];
    for (let j=0;j<(i<=10?5:4);j++) {
      const id=`p${passengerNumber}`;
      ids.push(id);
      catalog.passengers.push({id,name:`가상 이용자 ${passengerNumber}`,address:`가상도시 테스트길 ${i}-${j+1}`,note:'실제 개인정보가 아닌 가상 데이터'});
      passengerNumber++;
    }
    for (const period of ['morning','afternoon']) catalog.baseRoutes.push({
      id:`${period}-ops-${i}`,name:`가상 ${i}코스`,period,staffId:`s${i}`,vehicleId:`v${i}`,
      passengerIds:period==='morning'?[...ids]:[...ids].reverse(),
    });
  }
  return catalog;
}

function operationRequest(catalog,date,period,catalogVersion,requestId,expectedVersion=0) {
  const absentIds=period==='afternoon'?['p2']:[];
  const excludedIds=period==='afternoon'?['p5']:[];
  const removed=new Set([...absentIds,...excludedIds]);
  const start=period==='morning'?530:1005;
  return {date,period,catalogVersion,requestId,expectedVersion,absentIds,excludedIds,
    routes:catalog.baseRoutes.filter((r)=>r.period===period).map((r)=>{
      const ids=r.passengerIds.filter((id)=>!removed.has(id));
      return {baseRouteId:r.id,staffId:r.staffId,vehicleId:r.vehicleId,passengerIds:ids,
        estimatedVisitMinutes:Object.fromEntries(ids.map((id,index)=>[id,start+5+index*5])),
        startMinute:start,endMinute:period==='morning'?570:1105};
    })};
}
module.exports={operationsCatalog,operationRequest};
