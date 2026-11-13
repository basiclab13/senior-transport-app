'use strict';
const {Timestamp}=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const {idPattern}=require('./validation');

// Extra fields need explicit migration: replacement would silently lose them.
function validateExistingSchedule(data,date,period) {
  const allowed=['schemaVersion','catalogVersion','date','period','timezone','status','version','lastRequestId','routes','absentIds','excludedIds','confirmedBy','confirmedAt'];
  const routeFields=['baseRouteId','staffId','vehicleId','passengerIds','estimatedVisitMinutes','startMinute','endMinute'];
  const id=(value)=>typeof value==='string'&&idPattern.test(value);
  const ids=(value)=>Array.isArray(value)&&value.every(id)&&new Set(value).size===value.length;
  const record=(value)=>value&&typeof value==='object'&&!Array.isArray(value);
  if (!record(data)||Object.keys(data).some((key)=>!allowed.includes(key))||
      data.schemaVersion!==1||data.status!=='confirmed'||data.timezone!=='Asia/Seoul'||
      data.date!==date||data.period!==period||!Number.isSafeInteger(data.version)||data.version<1||
      !id(data.catalogVersion)||!id(data.lastRequestId)||typeof data.confirmedBy!=='string'||!data.confirmedBy||
      !(data.confirmedAt instanceof Timestamp)||!ids(data.absentIds)||!ids(data.excludedIds)||
      !Array.isArray(data.routes)||data.routes.length>100||data.routes.some((r)=>
        !record(r)||Object.keys(r).some((key)=>!routeFields.includes(key))||
        !id(r.baseRouteId)||!id(r.staffId)||!id(r.vehicleId)||!ids(r.passengerIds)||
        !record(r.estimatedVisitMinutes))) {
    throw new HttpsError('failed-precondition','기존 일정의 형식 또는 추가 필드를 확인해 주세요. 기존 문서는 보존됩니다. 별도 검토·변환 전에는 덮어쓸 수 없습니다.',{reason:'existing-schedule-incompatible'});
  }
}
module.exports={validateExistingSchedule};
