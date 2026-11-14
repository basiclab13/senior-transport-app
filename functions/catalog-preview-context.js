'use strict';
const {createHash}=require('node:crypto');
const {HttpsError}=require('firebase-functions/v2/https');
const VERSION='ai-test-25x80-v1';
const MANIFEST_HASH='1d9288075fc24a9f6c806f88eaa941b3bc535cc92a43de0c07c132e9034be38c';
const KIND='ai25-catalog-preview';
const SCENARIOS=['unchanged','passenger-absence','order-improvement','absence-capacity-improvement','staff-absence','five-staff-absent','six-staff-absent'];
const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
const hash=v=>createHash('sha256').update(JSON.stringify(canonical(v))).digest('hex');
function previewRequest(input){
  if(!input||typeof input!=='object'||!Object.hasOwn(input,'previewContext'))return {schedule:input};
  const {previewContext:preview,...schedule}=input;
  if(!preview||typeof preview!=='object'||Array.isArray(preview)||
    Object.keys(preview).sort().join(',')!=='kind,manifestSha256,scenario'||preview.kind!==KIND||
    !SCENARIOS.includes(preview.scenario)||preview.manifestSha256!==MANIFEST_HASH||
    schedule.catalogVersion!==VERSION||schedule.expectedVersion!==0) {
    throw new HttpsError('invalid-argument','허용된 가상 catalog 테스트 요청인지 확인해 주세요.');
  }
  return {schedule,contextReader:(db,uid,data)=>readPreviewContext(db,uid,data,preview)};
}
async function readPreviewContext(db,uid,input,preview){
  return db.runTransaction(async tx=>{
    // Do not read settings, schedules, staffSchedules or real absence records.
    const [profile,metadata]=await tx.getAll(db.doc(`users/${uid}`),db.doc(`catalogs/${VERSION}`));
    if(profile.data()?.active!==true||profile.data()?.role!=='admin')throw new HttpsError('permission-denied','관리자만 AI 테스트를 사용할 수 있습니다.');
    const meta=metadata.data();
    if(meta?.ready!==true||meta.fictional!==true||meta.testData!==true||meta.manifestSha256!==MANIFEST_HASH) {
      throw new HttpsError('failed-precondition','검증된 테스트 catalog를 확인해 주세요.');
    }
    const catalog={};
    for(const name of ['staff','vehicles','passengers','baseRoutes']) {
      const docs=await tx.get(db.collection(`catalogs/${VERSION}/${name}`));
      catalog[name]=docs.docs.map(d=>({...d.data(),id:d.id})).sort((a,b)=>a.id.localeCompare(b.id,'en',{numeric:true}));
    }
    // Match the immutable manifest's array order (period first, then route ID).
    catalog.baseRoutes.sort((a,b)=>['morning','afternoon'].indexOf(a.period)-['morning','afternoon'].indexOf(b.period)||a.id.localeCompare(b.id,'en',{numeric:true}));
    const {manifestSha256,...fields}=meta;
    if(hash(catalog)!==meta.fixture?.contentSha256||hash({catalogVersion:VERSION,metadata:fields,collections:catalog})!==MANIFEST_HASH) {
      throw new HttpsError('failed-precondition','테스트 catalog의 내용이 변경되었습니다. 다시 검증해 주세요.');
    }
    const count=preview.scenario==='staff-absence'?1:preview.scenario==='five-staff-absent'?5:preview.scenario==='six-staff-absent'?6:0;
    const absentStaffIds=meta.fixture.assignedStaffIds.slice(0,count);
    const versions=Object.fromEntries(catalog.staff.map(s=>[s.id,absentStaffIds.includes(s.id)?1:0]));
    const expected=input.expectedAvailabilityVersions;
    if(!expected||Object.keys(expected).length!==catalog.staff.length||catalog.staff.some(s=>expected[s.id]!==versions[s.id])) {
      throw new HttpsError('aborted','테스트 결근 상황이 변경되었습니다. 다시 요청해 주세요.');
    }
    const weekday=new Date(`${input.date}T00:00:00Z`).getUTCDay()||7;
    const available=catalog.staff.filter(s=>s.active===true&&!absentStaffIds.includes(s.id)&&!(s.unavailableWeekdays||[]).includes(weekday)).length;
    if(available<catalog.baseRoutes.filter(r=>r.period===input.period).length) {
      throw new HttpsError('failed-precondition','가용 직원이 부족해 모든 코스를 배정할 수 없습니다. 테스트 상황을 바꿔 주세요.');
    }
    return {catalog,versions,absentStaffIds};
  });
}
module.exports={previewRequest,VERSION,MANIFEST_HASH,KIND,SCENARIOS};
