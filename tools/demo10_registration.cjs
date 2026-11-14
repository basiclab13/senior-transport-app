'use strict';
const {isDeepStrictEqual}=require('node:util');
const {guard,PROJECT}=require('./ai25_registration.cjs');
const {sha}=require('./ai25_fixture.cjs');
const {VERSION,PREVIOUS,makePlan,baseline}=require('./demo10_fixture.cjs');
function scope(db,o){
  guard(db.projectId,o.env||process.env);
  if(db.databaseId!=='(default)')throw Error('DATABASE_MISMATCH');
  if(o.apply&&(o.confirmation!==db.projectId||o.approval!==o.target))throw Error('APPROVAL_REQUIRED');
}
async function topology(db,root){
  const collections=await db.doc(root).listCollections();
  let nested=0,documents=0;
  for(const c of collections)for(const doc of await c.listDocuments()){
    documents++;nested+=(await doc.listCollections()).length;
  }
  return {collections:collections.map(c=>c.id).sort(),documents,nested};
}
async function readCatalog(db,tx,version){
  const root=`catalogs/${version}`,parent=await tx.get(db.doc(root)),collections={};
  for(const name of ['staff','vehicles','passengers','baseRoutes']){
    const q=await tx.get(db.collection(`${root}/${name}`));
    collections[name]=q.docs.map(d=>({...d.data(),id:d.id}));
  }
  return {parent,collections};
}
function verified(current,manifest){
  const expected=manifest.collections;
  if(!current.parent.exists||current.parent.data().schemaVersion!==1||current.parent.data().ready!==true||current.parent.data().fictional!==true)return false;
  for(const k of Object.keys(expected)){
    const sort=a=>[...a].sort((x,y)=>x.id.localeCompare(y.id));
    if(!isDeepStrictEqual(sort(expected[k]),sort(current.collections[k])))return false;
  }
  if(manifest.catalogVersion===VERSION)return isDeepStrictEqual(current.parent.data(),makePlan(manifest).metadata);
  return true;
}
function contentHash(current,manifest){
  // Canonical manifest order, independent of Firestore's lexical document order.
  return sha(Object.fromEntries(Object.entries(manifest.collections).map(([name,items])=>{
    const byId=new Map(current.collections[name].map(d=>[d.id,d]));
    return [name,items.map(d=>byId.get(d.id)||null)];
  })));
}
async function register(db,manifest,o={}){
  scope(db,{...o,target:VERSION});const p=makePlan(manifest),top=await topology(db,p.parentPath);
  const result=await db.runTransaction(async tx=>{
    const current=await readCatalog(db,tx,VERSION),valid=verified(current,manifest)&&top.nested===0&&top.documents===58&&top.collections.length===4;
    const base={catalogVersion:VERSION,counts:p.counts,manifestSha256:p.manifestSha256,contentSha256:p.metadata.fixture.contentSha256,
      actualContentSha256:contentHash(current,manifest),
      existingChildren:Object.values(current.collections).reduce((n,a)=>n+a.length,0),verified:valid,createdDocuments:0};
    if(o.verify)return {...base,status:valid?'VERIFIED':'VERIFICATION_FAILED'};
    if(current.parent.exists||top.collections.length)return {...base,status:'BLOCKED_EXISTING_CATALOG'};
    if(!o.apply)return {...base,status:'DRY_RUN_OK',plannedDocuments:59};
    // Whole catalog is validated above; all reads precede all 59 create-only writes.
    for(const d of p.documents)tx.create(db.doc(d.path),d.data);
    tx.create(db.doc(p.parentPath),p.metadata);
    return {...base,status:'APPLIED',createdDocuments:59};
  });
  if(result.status==='APPLIED'){
    const after=await register(db,manifest,{...o,apply:false,verify:true});
    return {...result,actualContentSha256:after.actualContentSha256,verified:after.verified,status:after.verified?'APPLIED':'POST_WRITE_VERIFICATION_FAILED'};
  }
  return result;
}
async function transition(db,manifest,o={}){
  const rollback=o.rollback===true,target=rollback?PREVIOUS:VERSION,expected=rollback?VERSION:PREVIOUS;
  scope(db,{...o,target});makePlan(manifest);
  const pointer=db.doc('settings/schedules'),before=await pointer.get();
  if(before.data()?.catalogVersion!==expected)throw Error('POINTER_MISMATCH');
  const targetManifest=rollback?baseline():manifest;
  const top=await topology(db,`catalogs/${target}`);
  // Counts only: no photo bytes, profile details or UID are returned or logged.
  let photoRecords=0;
  for(let i=1;i<=10;i++)for(const root of ['workPhotoRecords','attendance'])
    photoRecords+=(await db.collection(`${root}/s${i}/records`).count().get()).data().count;
  const [ai,photo]=await db.getAll(db.doc('_aiControl/config'),db.doc('_workPhotoControl/config'));
  const allowed=doc=>Array.isArray(doc.data()?.allowedCatalogVersions)&&doc.data().allowedCatalogVersions.includes(target);
  const features={aiTestMode:ai.data()?.mode==='test',aiCatalogAllowed:allowed(ai),
    fictionalLocationTransmissionAllowed:ai.data()?.allowFictionalLocations===true,
    photoRegistrationEnabled:photo.data()?.enabled===true,photoCatalogAllowed:allowed(photo)};
  return db.runTransaction(async tx=>{
    const settings=await tx.get(pointer);
    if(!settings.exists||!settings.updateTime.isEqual(before.updateTime)||!isDeepStrictEqual(settings.data(),before.data()))throw Error('POINTER_CHANGED');
    const catalog=await readCatalog(db,tx,target);
    const wanted=Object.values(targetManifest.collections).reduce((n,a)=>n+a.length,0);
    if(!verified(catalog,targetManifest)||top.documents!==wanted||top.nested||top.collections.length!==4)throw Error('TARGET_CATALOG_INVALID');
    const accounts=await tx.get(db.collection('users').where('active','==',true));
    const staff=new Set(catalog.collections.staff.filter(s=>s.active===true).map(s=>s.id));
    const active=accounts.docs.map(d=>d.data()).filter(d=>d.role==='staff');
    const invalid=active.filter(a=>!staff.has(a.staffId)).length;
    const schedules=await tx.get(db.collection('schedules'));
    const versions={};for(const s of schedules.docs){const v=s.data().catalogVersion||'unknown';versions[v]=(versions[v]||0)+1;}
    const result={status:invalid?'BLOCKED_STAFF_MAPPING':o.apply?'SWITCHED':'DRY_RUN_OK',from:expected,to:target,
      checkedActiveStaffAccounts:active.length,invalidStaffMappings:invalid,existingSchedulesByCatalog:versions,preservedPhotoRecords:photoRecords,
      targetContentSha256:sha(targetManifest.collections),features,scheduleWrites:0,absenceWrites:0,photoWrites:0,accountWrites:0,
      notice:'Existing confirmed schedules remain pinned. Existing staff/date absences remain effective. Refresh all clients.'};
    if(o.apply&&!invalid)tx.update(pointer,{catalogVersion:target});
    return result;
  });
}
module.exports={register,transition,verified,PROJECT};
