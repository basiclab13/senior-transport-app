'use strict';
const {createHash}=require('node:crypto');
const {HttpsError}=require('firebase-functions/v2/https');
const {FieldValue}=require('firebase-admin/firestore');
const digest=v=>createHash('sha256').update(v).digest('hex');
function canonical(v) {
  if(Array.isArray(v))return v.map(canonical);
  if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])]));
  return v;
}
function check(control,profile,uid,catalogVersion,app) {
  if(profile?.active!==true||profile?.role!=='admin')throw new HttpsError('permission-denied','관리자만 AI 추천을 요청할 수 있습니다.');
  if(control?.mode!=='test')throw new HttpsError('failed-precondition','운영 AI가 비활성화되어 있습니다.');
  if(!Array.isArray(control.allowedAdminUids)||!control.allowedAdminUids.includes(uid)||
    !Array.isArray(control.allowedCatalogVersions)||!control.allowedCatalogVersions.includes(catalogVersion)) {
    throw new HttpsError('permission-denied','승인된 관리자와 가상 기본 데이터만 사용할 수 있습니다.');
  }
  if(control.requireAppCheck!==undefined&&typeof control.requireAppCheck!=='boolean')throw new HttpsError('failed-precondition','AI 서버 설정을 확인해 주세요.');
  if(control.requireAppCheck===true&&!app)throw new HttpsError('unauthenticated','앱 인증을 확인한 후 다시 요청해 주세요.');
  const bounded=(value,fallback,max)=>{
    const n=value??fallback;
    if(!Number.isInteger(n)||n<1||n>max)throw new HttpsError('failed-precondition','AI 사용 한도 설정을 확인해 주세요.');
    return n;
  };
  return {projectLimit:bounded(control.projectDailyLimit,100,100),adminLimit:bounded(control.adminDailyLimit,20,20),
    cooldownSeconds:bounded(control.cooldownSeconds,30,3600),allowFictionalLocations:control.allowFictionalLocations===true};
}
async function authorize(db,uid,input,app) {
  const [c,p]=await db.getAll(db.doc('_aiControl/config'),db.doc(`users/${uid}`));
  return check(c.data(),p.data(),uid,input.catalogVersion,app);
}
async function reserve(db,uid,input,app,now=Date.now()) {
  const key=digest(`${uid}:${input.requestId}`),hash=digest(JSON.stringify(canonical(input)));
  const day=new Date(now+9*3600000).toISOString().slice(0,10),admin=digest(uid);
  const ref=db.doc(`_aiRequests/${key}`),usage=db.doc(`_aiUsage/${day}`);
  const result=await db.runTransaction(async tx=>{
    const [r,u,c,p]=await tx.getAll(ref,usage,db.doc('_aiControl/config'),db.doc(`users/${uid}`));
    const policy=check(c.data(),p.data(),uid,input.catalogVersion,app);
    if(r.exists) {
      if(r.data().hash!==hash)return {error:'already-exists'};
      if(['reserved','running'].includes(r.data().state)&&r.data().expiresAtMs<=now)tx.update(ref,{state:'expired'});
      return {error:'already-exists'}; // Permanent tombstone; expiry never grants another API call.
    }
    const data=u.data()||{},own=data.admins?.[admin]||{count:0};
    const countValid=n=>Number.isSafeInteger(n)&&n>=0;
    if(u.exists&&(!countValid(data.count)||!data.admins||typeof data.admins!=='object'||Array.isArray(data.admins)||
      !countValid(data.activeUntilMs)||!countValid(own.count)||
      (own.lastAttemptMs!==undefined&&!countValid(own.lastAttemptMs)))) {
      throw new HttpsError('failed-precondition','AI 사용량 기록을 확인해 주세요.');
    }
    if((data.count||0)>=policy.projectLimit||own.count>=policy.adminLimit||
      (own.lastAttemptMs!==undefined&&now-own.lastAttemptMs<policy.cooldownSeconds*1000)||data.activeUntilMs>now) {
      return {error:'resource-exhausted'};
    }
    const expiresAtMs=now+120000;
    tx.create(ref,{hash,state:'reserved',day,expiresAtMs,createdAt:FieldValue.serverTimestamp()});
    tx.set(usage,{count:(data.count||0)+1,admins:{...data.admins,[admin]:{count:own.count+1,lastAttemptMs:now}},
      activeKey:key,activeUntilMs:expiresAtMs});
    return {key,day,hash,expiresAtMs,policy};
  });
  if(result.error)throw new HttpsError(result.error,result.error==='already-exists'?
    '이미 접수한 요청입니다. 결과가 없으면 상태를 확인한 후 새 요청으로 다시 시도해 주세요.':
    'AI 사용 한도에 도달했거나 다른 요청이 진행 중입니다. 잠시 후 다시 시도해 주세요.');
  return result;
}
async function claim(db,ticket,now=Date.now()) {
  const ref=db.doc(`_aiRequests/${ticket.key}`);
  const ok=await db.runTransaction(async tx=>{
    const r=await tx.get(ref),data=r.data();
    if(data?.state!=='reserved'||data.hash!==ticket.hash)return false;
    if(data.expiresAtMs<=now){tx.update(ref,{state:'expired'});return false;}
    tx.update(ref,{state:'running'});return true;
  });
  if(!ok)throw new HttpsError('aborted','AI 요청 예약이 만료되었거나 이미 사용되었습니다. 새 요청을 시작해 주세요.');
}
async function finish(db,ticket,success,now=Date.now()) {
  const ref=db.doc(`_aiRequests/${ticket.key}`),usage=db.doc(`_aiUsage/${ticket.day}`);
  return db.runTransaction(async tx=>{
    const [r,u]=await tx.getAll(ref,usage),data=r.data(),current=u.data();
    if(!data||!['reserved','running'].includes(data.state))return false;
    const valid=data.expiresAtMs>now&&current?.activeKey===ticket.key;
    tx.update(ref,{state:valid?(success?'completed':'failed'):'expired',finishedAt:FieldValue.serverTimestamp()});
    if(current?.activeKey===ticket.key)tx.update(usage,{activeKey:null,activeUntilMs:0});
    return valid;
  });
}
module.exports={authorize,reserve,claim,finish};
