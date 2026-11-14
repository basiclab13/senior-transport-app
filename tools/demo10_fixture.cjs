'use strict';
const {readFileSync}=require('node:fs');
const {join}=require('node:path');
const {isDeepStrictEqual}=require('node:util');
const {sha}=require('./ai25_fixture.cjs');
const {validateSchedule}=require('../functions/validation');
const VERSION='demo-10x24-v1',PREVIOUS='deploy-test-v2';
const COUNTS={staff:10,vehicles:8,passengers:24,baseRoutes:16};
const baseline=()=>JSON.parse(readFileSync(join(__dirname,'../docs/fixtures/deploy-test-v2.baseline.json'),'utf8'));
function requestFor(c,date='2026-12-07',period='morning',version=VERSION){
  return {date,period,catalogVersion:version,expectedVersion:0,requestId:`demo10-${date}-${period}`,absentIds:[],excludedIds:[],
    expectedAvailabilityVersions:Object.fromEntries(c.staff.map(s=>[s.id,0])),
    routes:c.baseRoutes.filter(r=>r.period===period).map(r=>({baseRouteId:r.id,staffId:r.staffId,vehicleId:r.vehicleId,
      passengerIds:[...r.passengerIds],estimatedVisitMinutes:{},estimatedVisitSources:{},startMinute:null,endMinute:null}))};
}
function buildManifest(){
  const old=baseline().collections,c=structuredClone(old);
  ['최지훈','정서연','강민준','조하은','윤도현','장수빈','임지우'].forEach((name,i)=>c.staff.push({id:`s${i+4}`,name,active:true,unavailableWeekdays:[]}));
  c.vehicles=c.vehicles.map(v=>({...v,passengerCapacity:4}));
  for(let i=4;i<=8;i++)c.vehicles.push({id:`v${i}`,name:`햇살 ${i}호`,passengerCapacity:4});
  const names=['김영숙','이정호','박순자','최상철','정미경','강명수','조정희','윤종수','장영자','임성호','한경자','오광수',
    '서옥순','신영수','권정숙','황태수','안미자','송재호','류춘자','홍진수','문복순','백동수','남혜숙','심만수'];
  c.passengers=names.map((name,i)=>{
    const previous=old.passengers[i],group=Math.floor(i/3),angle=2*Math.PI*group/8,radius=2+i%3;
    return {...(previous||{id:`p${i+1}`,address:`햇살연습마을 느티길 ${group+1}-${i%3+1}`,note:''}),name,
      fictionalLocation:{xKm:Number((radius*Math.cos(angle)).toFixed(6))||0,yKm:Number((radius*Math.sin(angle)).toFixed(6))||0}};
  });
  c.baseRoutes=c.baseRoutes.map(r=>({...r,passengerIds:r.staffId==='s2'?[...r.passengerIds,'p6']:[...r.passengerIds]}));
  for(const period of ['morning','afternoon'])for(let i=3;i<=8;i++)c.baseRoutes.push({id:`${period}-demo-${i}`,name:`${period==='morning'?'오전':'오후'} ${i}코스`,
    period,staffId:`s${i}`,vehicleId:`v${i}`,passengerIds:[0,1,2].map(j=>`p${(i-1)*3+j+1}`)});
  return {catalogVersion:VERSION,metadata:{schemaVersion:1,ready:true,fictional:true,testData:true,
    fixture:{id:VERSION,revision:1,provenance:'procedural-fiction-only',locationModel:'fictional-cartesian-km-not-gps',
      counts:COUNTS,assignedStaffIds:c.staff.slice(0,8).map(s=>s.id),reserveStaffIds:['s9','s10'],contentSha256:sha(c)}},collections:c};
}
function makePlan(manifest){
  if(!isDeepStrictEqual(manifest,buildManifest()))throw Error('FIXTURE_MANIFEST_MISMATCH');
  const c=manifest.collections;
  for(const [k,n]of Object.entries(COUNTS))if(c[k].length!==n)throw Error('COUNT_MISMATCH');
  if(new Set([...c.staff,...c.passengers].map(x=>x.name)).size!==34)throw Error('NAME_DUPLICATE');
  for(const period of ['morning','afternoon'])validateSchedule(requestFor(c,'2026-12-07',period),c);
  const manifestSha256=sha(manifest),parentPath=`catalogs/${VERSION}`;
  return {catalogVersion:VERSION,counts:COUNTS,parentPath,manifestSha256,metadata:{...manifest.metadata,manifestSha256},
    documents:Object.entries(c).flatMap(([name,items])=>items.map(({id,...data})=>({path:`${parentPath}/${name}/${id}`,data})))};
}
module.exports={VERSION,PREVIOUS,COUNTS,baseline,buildManifest,makePlan,requestFor};
