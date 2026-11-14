'use strict';
const {createHash}=require('node:crypto');
const {isDeepStrictEqual}=require('node:util');
const {validateSchedule}=require('../functions/validation');
const VERSION='ai-test-25x80-v1';
const STAFF_NAMES=['김다정','이온유','박여유','최지훈','정서연','강민준','조하은','윤도현','장수빈','임지우',
  '한서준','오예린','서현우','신유진','권지호','황다은','안태윤','송나연','류준서','홍소윤','문예준','백소희','남지안','심도윤','노채원'];
const FAMILIES=['김','이','박','최','정','강','조','윤','장','임'];
const GIVEN=['영숙','정호','순자','상철','미경','명수','정희','종수'];
const COUNTS={staff:25,vehicles:20,passengers:80,baseRoutes:40};
function canonical(v){return Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?
  Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;}
function sha(v){return createHash('sha256').update(JSON.stringify(canonical(v))).digest('hex');}
function buildManifest(){
  const staff=STAFF_NAMES.map((name,i)=>({id:`s${i+1}`,name,active:true,unavailableWeekdays:[]}));
  const vehicles=Array.from({length:20},(_,i)=>({id:`v${i+1}`,name:`${i+1}호차`,passengerCapacity:4}));
  const passengers=Array.from({length:80},(_,i)=>{
    const group=Math.floor(i/4),offset=i%4;
    // Entirely invented Cartesian points. No GPS, geocoding or external names.
    const angle=group===0?0:group===1?Math.PI:2*Math.PI*(group-2)/18;
    const radius=(group<2?10:2)+offset;
    return {id:`p${i+1}`,name:FAMILIES[Math.floor(i/8)]+GIVEN[i%8],
      address:`햇살연습마을 느티길 ${group+1}-${offset+1}`,note:offset===0?'승하차 시 천천히 안내':'',
      fictionalLocation:{xKm:Number((radius*Math.cos(angle)).toFixed(6)),yKm:Number((radius*Math.sin(angle)).toFixed(6))}};
  });
  const baseRoutes=['morning','afternoon'].flatMap(period=>Array.from({length:20},(_,i)=>({
    id:`${period}-ai-${String(i+1).padStart(2,'0')}`,name:`${period==='morning'?'오전':'오후'} ${i+1}코스`,period,staffId:`s${i+1}`,vehicleId:`v${i+1}`,
    passengerIds:Array.from({length:4},(_,j)=>`p${i*4+j+1}`)})));
  const collections={staff,vehicles,passengers,baseRoutes};
  return {catalogVersion:VERSION,metadata:{schemaVersion:1,ready:true,fictional:true,testData:true,
    fixture:{id:'ai-25-staff-80-passengers',revision:1,provenance:'procedural-fiction-only',
      locationModel:'fictional-cartesian-km-not-gps',counts:COUNTS,
      assignedStaffIds:staff.slice(0,20).map(s=>s.id),reserveStaffIds:staff.slice(20).map(s=>s.id),contentSha256:sha(collections)}},collections};
}
function requestFor(catalog,date='2026-12-07',period='morning',requestId='ai25-local-preview'){
  const first=period==='morning'?540:1020;
  return {date,period,catalogVersion:VERSION,requestId,expectedVersion:0,absentIds:[],excludedIds:[],
    expectedAvailabilityVersions:Object.fromEntries(catalog.staff.map(s=>[s.id,0])),
    routes:catalog.baseRoutes.filter(r=>r.period===period).map(r=>({baseRouteId:r.id,staffId:r.staffId,vehicleId:r.vehicleId,
      passengerIds:[...r.passengerIds],estimatedVisitMinutes:Object.fromEntries(r.passengerIds.map((id,i)=>[id,first+5*i])),
      estimatedVisitSources:Object.fromEntries(r.passengerIds.map(id=>[id,'manual'])),startMinute:first-10,endMinute:first+40}))};
}
function makePlan(manifest){
  if(!isDeepStrictEqual(manifest,buildManifest()))throw new Error('FIXTURE_MANIFEST_MISMATCH');
  const catalog=manifest.collections;
  const names=[...catalog.staff,...catalog.passengers].map(d=>d.name);
  if(new Set(names).size!==105||names.some(n=>n.includes('가상')))throw new Error('FIXTURE_NAMES_INVALID');
  for(const items of Object.values(catalog))if(new Set(items.map(d=>d.name)).size!==items.length)throw new Error('FIXTURE_NAMES_INVALID');
  for(const name of Object.keys(COUNTS))if(catalog[name].length!==COUNTS[name])throw new Error('FIXTURE_COUNT_INVALID');
  for(const period of ['morning','afternoon'])validateSchedule(requestFor(catalog,'2026-12-07',period),catalog);
  const parentPath=`catalogs/${VERSION}`,manifestSha256=sha(manifest);
  return {catalogVersion:VERSION,counts:COUNTS,parentPath,metadata:{...manifest.metadata,manifestSha256},manifestSha256,
    documents:Object.entries(catalog).flatMap(([collection,items])=>items.map(({id,...data})=>({path:`${parentPath}/${collection}/${id}`,data})))};
}
function scenario(name,period='morning'){
  const catalog=buildManifest().collections,input=requestFor(catalog,'2026-12-07',period);
  const answer=()=>({routes:input.routes.map(r=>({baseRouteId:r.baseRouteId,staffId:r.staffId,passengerIds:[...r.passengerIds]})),reasons:['고정된 가상 검증 응답']});
  const remove=(route,id)=>{route.passengerIds=route.passengerIds.filter(p=>p!==id);delete route.estimatedVisitMinutes[id];delete route.estimatedVisitSources[id];};
  if(name==='order-improvement'){
    input.routes[0].passengerIds=['p1','p3','p2','p4'];
    input.routes[0].estimatedVisitMinutes.p3=input.routes[0].estimatedVisitMinutes.p1+5;
    input.routes[0].estimatedVisitMinutes.p2=input.routes[0].estimatedVisitMinutes.p1+10;
    const proposal=answer();proposal.routes[0].passengerIds=['p1','p2','p3','p4'];return {catalog,input,proposal};
  }
  if(name==='absence-capacity-improvement'){
    const a=input.routes[0],b=input.routes[1];
    a.passengerIds=['p5','p2','p3','p4'];b.passengerIds=['p1','p6','p7','p8'];
    const t=a.estimatedVisitMinutes.p1;delete a.estimatedVisitMinutes.p1;delete a.estimatedVisitSources.p1;
    const u=b.estimatedVisitMinutes.p5;delete b.estimatedVisitMinutes.p5;delete b.estimatedVisitSources.p5;
    a.estimatedVisitMinutes.p5=u;a.estimatedVisitSources.p5='manual';b.estimatedVisitMinutes.p1=t;b.estimatedVisitSources.p1='manual';
    input.absentIds=['p2'];remove(a,'p2');
    const proposal=answer();proposal.routes[0].passengerIds=['p5','p1','p3','p4'];proposal.routes[1].passengerIds=['p6','p7','p8'];
    return {catalog,input,proposal};
  }
  if(name==='passenger-absence'){input.absentIds=['p2'];remove(input.routes[0],'p2');}
  else if(name==='staff-absence'||name==='five-staff-absent'||name==='six-staff-absent'){
    const count=name==='staff-absence'?1:name==='five-staff-absent'?5:6;
    const absentStaffIds=input.routes.slice(0,count).map(r=>r.staffId);
    input.expectedAvailabilityVersions=Object.fromEntries(catalog.staff.map(s=>[s.id,absentStaffIds.includes(s.id)?1:0]));
    const proposal=answer();proposal.routes.slice(0,Math.min(count,5)).forEach((r,i)=>{r.staffId=`s${21+i}`;});
    return {catalog,input,proposal,absentStaffIds};
  } else if(name!=='unchanged')throw new Error('UNKNOWN_SCENARIO');
  return {catalog,input,proposal:answer(),absentStaffIds:[]};
}
const SCENARIOS=['unchanged','passenger-absence','order-improvement','absence-capacity-improvement','staff-absence','five-staff-absent','six-staff-absent'];
module.exports={VERSION,COUNTS,buildManifest,makePlan,requestFor,scenario,SCENARIOS,sha};
