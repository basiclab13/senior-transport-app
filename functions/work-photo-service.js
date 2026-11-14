'use strict';
const {createHash,randomUUID}=require('node:crypto');
const {HttpsError}=require('firebase-functions/v2/https');
const {FieldValue,Timestamp}=require('firebase-admin/firestore');
const {absenceData}=require('./staff-absence-service');
const {isDeepStrictEqual}=require('node:util');
const MAX_BYTES=184320,DAY=86400000,PREFIX='workPhotos/v1/';
const digest=v=>createHash('sha256').update(v).digest('hex');
const fail=(code,message)=>{throw new HttpsError(code,message);};
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,80}$/.test(v);
function datePeriod(input){
  if(!input||typeof input!=='object'||Array.isArray(input)||typeof input.date!=='string'||
    !/^\d{4}-\d{2}-\d{2}$/.test(input.date)||!Number.isFinite(Date.parse(input.date))||
    new Date(input.date).toISOString().slice(0,10)!==input.date||!['morning','afternoon'].includes(input.period))fail('invalid-argument','날짜와 오전·오후를 확인해 주세요.');
}
async function jpeg(base64){
  if(typeof base64!=='string'||base64.length>Math.ceil(MAX_BYTES/3)*4||!base64.length||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(base64))fail('invalid-argument','180KiB 이하 JPEG 사진을 선택해 주세요.');
  const input=Buffer.from(base64,'base64');
  if(!input.length||input.length>MAX_BYTES||input.toString('base64')!==base64)fail('invalid-argument','사진 형식을 확인해 주세요.');
  try{
    const sharp=require('sharp');
    const image=sharp(input,{limitInputPixels:4000000,failOn:'warning'}),meta=await image.metadata();
    if(meta.format!=='jpeg'||!meta.width||!meta.height||meta.width*meta.height>4000000||(meta.pages||1)!==1)throw Error('format');
    const result=await image.rotate().jpeg({quality:80}).toBuffer();
    if(!result.length||result.length>MAX_BYTES)throw Error('size');
    return result; // Re-encoding strips EXIF and original file metadata.
  }catch{fail('invalid-argument','사진을 읽을 수 없습니다. 작은 JPEG 사진을 다시 선택해 주세요.');}
}
function active(profile){if(profile?.active!==true||!['staff','admin'].includes(profile.role))fail('permission-denied','활성 계정으로 로그인해 주세요.');}
async function registrationContext(tx,db,uid,input,app){
  const profile=(await tx.get(db.doc(`users/${uid}`))).data();active(profile);
  if(profile.role!=='staff'||!id(profile.staffId))fail('permission-denied','직원 본인의 사진만 등록할 수 있습니다.');
  const staffId=profile.staffId,key=`${input.date}_${input.period}`;
  const [schedule,projection,absence,control]=await tx.getAll(db.doc(`schedules/${key}`),db.doc(`staffSchedules/${staffId}/days/${key}`),
    db.doc(`staffAvailability/${input.date}/staff/${staffId}`),db.doc('_workPhotoControl/config'));
  const config=control.data();
  if(config?.enabled!==true)fail('failed-precondition','사진 등록이 비활성 상태입니다. 관리자에게 문의해 주세요.');
  if(config.requireAppCheck!==undefined&&typeof config.requireAppCheck!=='boolean')fail('failed-precondition','사진 서버 설정을 확인해 주세요.');
  if(config.requireAppCheck===true&&!app)fail('unauthenticated','앱 인증을 확인해 주세요.');
  const main=schedule.data(),own=projection.data();
  if(!main||!own||main.status!=='confirmed'||own.status!=='confirmed'||own.staffId!==staffId||
    main.date!==input.date||main.period!==input.period||own.date!==input.date||own.period!==input.period||
    !Number.isSafeInteger(main.version)||main.version<1||main.version!==input.expectedVersion||own.version!==main.version||
    !id(main.catalogVersion)||main.catalogVersion!==own.catalogVersion||!Array.isArray(own.routes)||own.routes.length!==1||
    own.routes[0].baseRouteId!==input.routeId||own.routes[0].staffId!==staffId||
    !Array.isArray(main.routes)||main.routes.filter(r=>r.staffId===staffId).length!==1||
    !isDeepStrictEqual(main.routes.find(r=>r.staffId===staffId),own.routes[0]))fail('failed-precondition','확정된 담당 일정이 변경되었습니다. 내 일정을 다시 확인해 주세요.');
  if(!Array.isArray(config.allowedCatalogVersions)||!config.allowedCatalogVersions.includes(main.catalogVersion))fail('permission-denied','허용된 가상 일정에서만 사진을 등록할 수 있습니다.');
  const [catalog,person]=await tx.getAll(db.doc(`catalogs/${main.catalogVersion}`),db.doc(`catalogs/${main.catalogVersion}/staff/${staffId}`));
  if(catalog.data()?.ready!==true||catalog.data()?.fictional!==true||person.data()?.active!==true)fail('failed-precondition','직원 연결과 가상 기본 데이터를 확인해 주세요.');
  const availability=absenceData(absence,input.date,staffId);
  if(availability.unavailablePeriods.includes(input.period)||availability.version!==input.expectedAvailabilityVersion)fail('failed-precondition','결근 정보가 변경되었습니다. 내 일정을 다시 확인해 주세요.');
  return {staffId,catalogVersion:main.catalogVersion,scheduleVersion:main.version,availabilityVersion:availability.version};
}
function recordRef(db,staffId,input,kind=input.kind){return db.doc(`workPhotoRecords/${staffId}/records/${input.date}_${input.period}_${input.routeId}_${kind}`);}
function publicRecord(doc){
  const d=doc.data();return {recordId:doc.id,staffId:d.staffId,date:d.date,period:d.period,routeId:d.routeId,kind:d.kind,
    registeredAt:d.registeredAt.toDate().toISOString(),expiresAt:d.expiresAt.toDate().toISOString()};
}
async function registerWorkPhoto(db,bucket,uid,input,{clock=Date.now,afterUpload=async()=>{},app}={}){
  if(!uid)fail('unauthenticated','로그인이 필요합니다.');datePeriod(input);
  const keys=['date','period','routeId','kind','requestId','photoBase64','expectedVersion','expectedAvailabilityVersion'];
  if(Object.keys(input).some(k=>!keys.includes(k))||!id(input.routeId)||!id(input.requestId)||!['start','end'].includes(input.kind)||
    !Number.isSafeInteger(input.expectedVersion)||input.expectedVersion<1||!Number.isSafeInteger(input.expectedAvailabilityVersion)||input.expectedAvailabilityVersion<0)fail('invalid-argument','사진 등록 요청을 확인해 주세요.');
  if(input.date!==new Date(clock()+9*3600000).toISOString().slice(0,10))fail('failed-precondition','사진은 한국 시간 기준 오늘의 확정 일정에만 등록할 수 있습니다.');
  const initialProfile=(await db.doc(`users/${uid}`).get()).data();active(initialProfile);
  if(initialProfile.role!=='staff'||!id(initialProfile.staffId))fail('permission-denied','직원 본인의 사진만 등록할 수 있습니다.');
  const bytes=await jpeg(input.photoBase64),sha256=digest(bytes),operationId=digest(`${uid}:${input.requestId}`),lease=randomUUID();
  const fingerprint=digest(JSON.stringify(Object.fromEntries(Object.entries({...input,photoBase64:sha256}).sort(([a],[b])=>a.localeCompare(b)))));
  const opRef=db.doc(`_workPhotoOperations/${operationId}`);
  const ticket=await db.runTransaction(async tx=>{
    const context=await registrationContext(tx,db,uid,input,app);
    const config=(await tx.get(db.doc('_workPhotoControl/config'))).data();
    if(config.requireAppCheck===true&&!app)fail('unauthenticated','앱 인증을 확인해 주세요.');
    if(config.requireAppCheck!==undefined&&typeof config.requireAppCheck!=='boolean')fail('failed-precondition','사진 서버 설정을 확인해 주세요.');
    const ref=recordRef(db,context.staffId,input),slot=db.doc(`_workPhotoSlots/${digest(ref.path)}`);
    const [op,existing,start,locked]=await tx.getAll(opRef,ref,recordRef(db,context.staffId,input,'start'),slot);
    if(op.exists&&(op.data().fingerprint!==fingerprint||op.data().uid!==uid))fail('already-exists','같은 요청 ID를 다른 사진에 사용할 수 없습니다.');
    if(existing.exists){
      if(existing.data().operationId===operationId&&existing.data().uid===uid)return {completed:publicRecord(existing)};
      fail('already-exists','이미 등록된 사진이 있습니다. 기록을 새로 확인해 주세요.');
    }
    if(input.kind==='end'&&(!start.exists||start.data().schemaVersion!==2||start.data().uid!==uid||start.data().expiresAt.toMillis()<=clock()))fail('failed-precondition','업무 시작 사진부터 등록해 주세요.');
    if(op.exists&&op.data().state!=='pending')fail('failed-precondition','종료된 요청입니다. 기록을 확인한 뒤 새 요청을 시작해 주세요.');
    if(locked.exists&&locked.data().leaseUntilMs>clock())fail('aborted','사진 등록을 처리 중입니다. 잠시 후 기록을 확인해 주세요.');
    const path=`${PREFIX}${context.staffId}/${input.date}/${input.period}/${input.routeId}/${input.kind}/${operationId}.jpg`;
    const value={...context,uid,date:input.date,period:input.period,routeId:input.routeId,kind:input.kind,
      operationId,fingerprint,path,sha256,size:bytes.length,bucket:bucket.name,state:'pending',lease,leaseUntilMs:clock()+120000,
      createdAtMs:op.data()?.createdAtMs??clock()};
    tx.set(opRef,value);tx.set(slot,{operationId,lease,leaseUntilMs:value.leaseUntilMs});
    return {...value,ref,slot};
  });
  if(ticket.completed)return ticket.completed;
  const file=bucket.file(ticket.path);
  try{
    try{await file.save(bytes,{resumable:false,preconditionOpts:{ifGenerationMatch:0},metadata:{contentType:'image/jpeg',cacheControl:'private, no-store',metadata:{sha256}}});}
    catch(error){if(Number(error.code)!==412)throw error;}
    const [meta]=await file.getMetadata();
    if(meta.contentType!=='image/jpeg'||Number(meta.size)!==bytes.length||meta.metadata?.sha256!==sha256)fail('data-loss','저장한 사진을 검증하지 못했습니다. 관리자에게 문의해 주세요.');
    await afterUpload();
    await db.runTransaction(async tx=>{
      const context=await registrationContext(tx,db,uid,input,app);
      const [op,existing,start,locked,control]=await tx.getAll(opRef,ticket.ref,recordRef(db,context.staffId,input,'start'),ticket.slot,db.doc('_workPhotoControl/config'));
      if(control.data()?.requireAppCheck===true&&!app)fail('unauthenticated','앱 인증을 확인해 주세요.');
      if(context.staffId!==ticket.staffId||context.catalogVersion!==ticket.catalogVersion||context.scheduleVersion!==ticket.scheduleVersion||context.availabilityVersion!==ticket.availabilityVersion||
        op.data()?.state!=='pending'||op.data()?.lease!==lease||locked.data()?.lease!==lease||op.data().leaseUntilMs<=clock())fail('aborted','사진 처리 중 담당 일정이나 요청 상태가 변경되었습니다. 기록을 확인해 주세요.');
      if(existing.exists)fail('already-exists','이미 등록된 사진입니다.');
      if(input.kind==='end'&&(!start.exists||start.data().uid!==uid||start.data().expiresAt.toMillis()<=clock()))fail('failed-precondition','업무 시작 기록을 확인해 주세요.');
      tx.create(ticket.ref,{schemaVersion:2,...context,uid,date:input.date,period:input.period,routeId:input.routeId,kind:input.kind,operationId,
        registeredAt:FieldValue.serverTimestamp(),expiresAt:Timestamp.fromMillis(clock()+30*DAY),
        photo:{bucket:bucket.name,path:ticket.path,generation:String(meta.generation),sha256,size:bytes.length,contentType:'image/jpeg'}});
      tx.update(opRef,{state:'completed',generation:String(meta.generation),completedAt:FieldValue.serverTimestamp()});
      tx.delete(ticket.slot);
    });
    return publicRecord(await ticket.ref.get());
  }catch(error){
    // Keep a resumable reservation after an uncertain upload/commit acknowledgement.
    // Never delete an object here: a concurrent retry may be about to commit it.
    const saved=await ticket.ref.get().catch(()=>null);
    if(saved?.data()?.operationId===operationId&&saved.data().uid===uid)return publicRecord(saved);
    if(error instanceof HttpsError)throw error;
    fail('unavailable','등록 완료 여부를 확인하지 못했습니다. 기록을 새로 확인한 뒤 같은 사진으로 다시 시도해 주세요.');
  }
}
async function getWorkPhotos(db,bucket,uid,input,{clock=Date.now,app}={}){
  if(!uid)fail('unauthenticated','로그인이 필요합니다.');datePeriod(input);
  if(Object.keys(input).some(k=>!['staffId','date','period','recordId','cursor'].includes(k))||!id(input.staffId)||
    (input.recordId!==undefined&&!/^[A-Za-z0-9_-]{1,200}$/.test(input.recordId))||
    (input.cursor!==undefined&&!/^[A-Za-z0-9_-]{1,200}$/.test(input.cursor)))fail('invalid-argument','조회할 사진 기록을 확인해 주세요.');
  async function authorize(){const [profile,control]=await db.getAll(db.doc(`users/${uid}`),db.doc('_workPhotoControl/config'));
    const p=profile.data(),c=control.data();active(p);
    if(c?.requireAppCheck!==undefined&&typeof c.requireAppCheck!=='boolean')fail('failed-precondition','사진 서버 설정을 확인해 주세요.');
    if(c?.requireAppCheck===true&&!app)fail('unauthenticated','앱 인증을 확인해 주세요.');
    if(p.role!=='admin'&&(p.role!=='staff'||p.staffId!==input.staffId))fail('permission-denied','본인의 사진만 볼 수 있습니다.');return p;}
  const p=await authorize(),records=db.collection(`workPhotoRecords/${input.staffId}/records`);
  if(!input.recordId){
    const prefix=`${input.date}_${input.period}_`;
    if(input.cursor&&!input.cursor.startsWith(prefix))fail('invalid-argument','조회 페이지를 확인해 주세요.');
    let query=records.orderBy('__name__').startAt(prefix).endAt(`${prefix}\uf8ff`).limit(20);if(input.cursor)query=query.startAfter(input.cursor);
    // Existing legacy documents remain intact. Filter before returning; no composite index needed.
    const result=await query.get();
    const visible=result.docs.filter(doc=>{const d=doc.data();return d.schemaVersion===2&&d.staffId===input.staffId&&d.date===input.date&&d.period===input.period&&d.expiresAt.toMillis()>clock()&&(p.role==='admin'||d.uid===uid);});
    await authorize();return {records:visible.map(publicRecord),nextCursor:result.size===20?result.docs.at(-1).id:null};
  }
  const doc=await records.doc(input.recordId).get(),d=doc.data();
  if(!d||d.schemaVersion!==2||d.staffId!==input.staffId||d.date!==input.date||d.period!==input.period||d.expiresAt.toMillis()<=clock()||
    (p.role!=='admin'&&d.uid!==uid))fail('not-found','사진 기록이 없거나 보관 기간이 지났습니다.');
  if(d.photo?.bucket!==bucket.name||!d.photo.path.startsWith(`${PREFIX}${input.staffId}/`)||!/^\d+$/.test(d.photo.generation))fail('data-loss','사진 저장 정보를 확인해 주세요.');
  const [bytes]=await bucket.file(d.photo.path,{generation:d.photo.generation}).download({validation:'crc32c'});
  if(bytes.length>MAX_BYTES||bytes.length!==d.photo.size||digest(bytes)!==d.photo.sha256)fail('data-loss','사진 파일을 검증하지 못했습니다.');
  const latest=await authorize();if(latest.role!=='admin'&&d.uid!==uid)fail('permission-denied','사진 조회 권한이 변경되었습니다.');
  if(d.expiresAt.toMillis()<=clock())fail('not-found','사진 보관 기간이 지났습니다.');
  return {...publicRecord(doc),photoBase64:bytes.toString('base64')};
}
// Manual only. No scheduled function is exported or deployed.
async function cleanupWorkPhotos(db,bucket,{apply=false,clock=Date.now}={}){
  const report={pending:0,expired:0,deleted:0};
  const ops=await db.collection('_workPhotoOperations').get();
  for(const doc of ops.docs){const op=doc.data();
    if(op.bucket!==bucket.name||!id(op.staffId)||!id(op.routeId)||!['start','end'].includes(op.kind)||
      !/^\d{4}-\d{2}-\d{2}$/.test(op.date)||!['morning','afternoon'].includes(op.period)||
      op.path!==`${PREFIX}${op.staffId}/${op.date}/${op.period}/${op.routeId}/${op.kind}/${doc.id}.jpg`)continue;
    const ref=recordRef(db,op.staffId,op),slot=db.doc(`_workPhotoSlots/${digest(ref.path)}`);
    const record=await ref.get();
    const expired=record.exists&&record.data().schemaVersion===2&&record.data().operationId===doc.id&&record.data().expiresAt.toMillis()<=clock();
    const pending=(!record.exists||record.data().operationId!==doc.id)&&['pending','deleting'].includes(op.state)&&op.createdAtMs+DAY<=clock()&&op.leaseUntilMs<=clock();
    if(!expired&&!pending)continue;report[expired?'expired':'pending']++;
    if(!apply)continue;
    const claimed=await db.runTransaction(async tx=>{
      const [current,r,lock]=await tx.getAll(doc.ref,ref,slot),value=current.data();
      if(!value||value.path!==op.path||value.lease!==op.lease||value.leaseUntilMs>clock())return false;
      if(r.exists&&r.data().operationId===doc.id&&r.data().expiresAt.toMillis()>clock())return false;
      tx.update(doc.ref,{state:'deleting'});return true;
    });
    if(!claimed)continue;
    try{
      const file=bucket.file(op.path),[metadata]=await file.getMetadata();
      if(metadata.metadata?.sha256!==op.sha256)fail('data-loss','정리 대상 파일이 일치하지 않습니다.');
      if(op.generation&&String(metadata.generation)!==op.generation)fail('data-loss','정리 대상 파일 버전이 변경되었습니다.');
      await file.delete({ifGenerationMatch:metadata.generation});
    }catch(error){if(Number(error.code)!==404)throw error;}
    await db.runTransaction(async tx=>{
      const [current,r,lock]=await tx.getAll(doc.ref,ref,slot);
      if(current.data()?.state!=='deleting')return;
      if(r.exists&&r.data().operationId===doc.id)tx.delete(ref);
      if(lock.data()?.operationId===doc.id)tx.delete(slot);
      tx.update(doc.ref,{state:'deleted',deletedAt:FieldValue.serverTimestamp()});
    });report.deleted++;
  }return report;
}
module.exports={registerWorkPhoto,getWorkPhotos,cleanupWorkPhotos,jpeg,MAX_BYTES};
