'use strict';
const {HttpsError}=require('firebase-functions/v2/https');
const {FieldValue}=require('firebase-admin/firestore');
const {idPattern}=require('./validation');
const fail=(code,message)=>{throw new HttpsError(code,message);};
function versionOf(data){
  if(!data)return 0;
  if(!Number.isSafeInteger(data.version)||data.version<1||typeof data.note!=='string'||data.note.length>2000||
    (data.defaultMorningMinute!==null&&(!Number.isInteger(data.defaultMorningMinute)||data.defaultMorningMinute<0||data.defaultMorningMinute>1439)))fail('failed-precondition','어르신 정보를 다시 확인해 주세요.');
  return data.version;
}
function validId(id){return typeof id==='string'&&idPattern.test(id);}
async function getPassengerDetails(db,uid,input){
  if(!uid)fail('unauthenticated','로그인이 필요합니다.');
  if(!input||Object.keys(input).some(k=>!['catalogVersion','date','period'].includes(k))||!validId(input.catalogVersion)||
    !/^\d{4}-\d{2}-\d{2}$/.test(input.date||'')||!['morning','afternoon'].includes(input.period))fail('invalid-argument','조회할 일정을 확인해 주세요.');
  return db.runTransaction(async tx=>{
    const [profile,metadata]=await tx.getAll(db.doc(`users/${uid}`),db.doc(`catalogs/${input.catalogVersion}`));
    const p=profile.data();
    if(p?.active!==true||!['admin','staff'].includes(p.role))fail('permission-denied','정보를 조회할 권한이 없습니다.');
    if(metadata.data()?.ready!==true||metadata.data()?.fictional!==true)fail('failed-precondition','어르신 기본 정보를 확인해 주세요.');
    let docs;
    if(p.role==='admin')docs=(await tx.get(db.collection(`catalogs/${input.catalogVersion}/passengerSettings`))).docs;
    else{
      if(!validId(p.staffId))fail('permission-denied','직원 연결을 확인해 주세요.');
      const [own,person]=await tx.getAll(db.doc(`staffSchedules/${p.staffId}/days/${input.date}_${input.period}`),db.doc(`catalogs/${input.catalogVersion}/staff/${p.staffId}`));
      const schedule=own.data();
      if(person.data()?.active!==true||!schedule||schedule.status!=='confirmed'||schedule.staffId!==p.staffId||schedule.catalogVersion!==input.catalogVersion||schedule.date!==input.date||schedule.period!==input.period||!Array.isArray(schedule.routes)||schedule.routes.some(r=>r.staffId!==p.staffId))fail('permission-denied','본인의 확정 일정만 조회할 수 있습니다.');
      const ids=[...new Set(schedule.routes.flatMap(r=>r.passengerIds))];
      if(ids.some(id=>!validId(id))||ids.length>100)fail('failed-precondition','담당 어르신 정보를 확인해 주세요.');
      docs=ids.length?await tx.getAll(...ids.map(id=>db.doc(`catalogs/${input.catalogVersion}/passengerSettings/${id}`))):[];
    }
    return {passengers:docs.filter(d=>d.exists).map(d=>{const v=d.data();versionOf(v);return {id:d.id,note:v.note,defaultMorningMinute:v.defaultMorningMinute,detailsVersion:v.version};})};
  });
}
async function updatePassengerDetails(db,uid,input){
  if(!uid)fail('unauthenticated','로그인이 필요합니다.');
  if(!input||Object.keys(input).some(k=>!['catalogVersion','passengerId','expectedVersion','note','defaultMorningMinute'].includes(k))||
    !validId(input.catalogVersion)||!validId(input.passengerId)||!Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<0||typeof input.note!=='string'||input.note.length>2000||
    (input.defaultMorningMinute!==null&&(!Number.isInteger(input.defaultMorningMinute)||input.defaultMorningMinute<0||input.defaultMorningMinute>1439)))fail('invalid-argument','특이사항은 2,000자 이내로, 약속 시간은 올바른 시각으로 입력해 주세요.');
  const parent=db.doc(`catalogs/${input.catalogVersion}`),ref=parent.collection('passengerSettings').doc(input.passengerId);
  return db.runTransaction(async tx=>{
    const [profile,metadata,person,old]=await tx.getAll(db.doc(`users/${uid}`),parent,parent.collection('passengers').doc(input.passengerId),ref);
    if(profile.data()?.active!==true||profile.data()?.role!=='admin')fail('permission-denied','관리자만 어르신 정보를 변경할 수 있습니다.');
    if(metadata.data()?.ready!==true||metadata.data()?.fictional!==true||!person.exists)fail('failed-precondition','등록된 어르신 정보를 확인해 주세요.');
    if(versionOf(old.data())!==input.expectedVersion)fail('aborted','다른 관리자가 어르신 정보를 변경했습니다. 다시 불러와 주세요.');
    const data={note:input.note.trim(),defaultMorningMinute:input.defaultMorningMinute,version:input.expectedVersion+1};
    tx.set(ref,{...data,updatedBy:uid,updatedAt:FieldValue.serverTimestamp()});
    return {id:input.passengerId,note:data.note,defaultMorningMinute:data.defaultMorningMinute,detailsVersion:data.version};
  });
}
module.exports={getPassengerDetails,updatePassengerDetails,versionOf};
