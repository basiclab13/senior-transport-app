'use strict';
const {isDeepStrictEqual}=require('node:util');
const {makePlan,requestFor,sha,VERSION}=require('./ai25_fixture.cjs');
const {validateSchedule}=require('../functions/validation');
const PROJECT='senior-transport-app';
function guard(project,env=process.env){
  if(project===PROJECT){
    if(['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','FIREBASE_EMULATOR_HUB',
      'FUNCTIONS_EMULATOR','FUNCTIONS_EMULATOR_HOST','FIREBASE_STORAGE_EMULATOR_HOST'].some(k=>env[k]))throw new Error('UNEXPECTED_EMULATOR_ENVIRONMENT');
  }else{
    if(!/^demo-[a-z0-9-]+$/.test(project||'')||!/^(127\.0\.0\.1|localhost):\d{1,5}$/.test(env.FIRESTORE_EMULATOR_HOST||''))throw new Error('DEMO_LOOPBACK_REQUIRED');
    const port=Number(env.FIRESTORE_EMULATOR_HOST.split(':').pop());if(port<1||port>65535)throw new Error('DEMO_LOOPBACK_REQUIRED');
  }
  for(const key of ['GCLOUD_PROJECT','GOOGLE_CLOUD_PROJECT'])if(env[key]&&env[key]!==project)throw new Error('PROJECT_MISMATCH');
  if(env.FIREBASE_CONFIG){let config;try{config=JSON.parse(env.FIREBASE_CONFIG);}catch{throw new Error('PROJECT_MISMATCH');}
    if(!config||typeof config!=='object'||Array.isArray(config)||(config.projectId&&config.projectId!==project))throw new Error('PROJECT_MISMATCH');}
}
async function collectionCheck(db,plan){
  const collections=await db.doc(plan.parentPath).listCollections();
  const topology={unexpectedCollections:collections.filter(c=>!Object.hasOwn(plan.counts,c.id)).length,
    existingCollectionCount:collections.length,nestedCollections:0,listedDocuments:{}};
  const refs=[];
  for(const collection of collections.filter(c=>Object.hasOwn(plan.counts,c.id))){
    // listDocuments includes missing parent documents that have descendants.
    const documents=await collection.listDocuments();
    topology.listedDocuments[collection.id]=documents.length;refs.push(...documents);
  }
  for(let i=0;i<refs.length;i+=12){
    const nested=await Promise.all(refs.slice(i,i+12).map(ref=>ref.listCollections()));
    topology.nestedCollections+=nested.reduce((sum,items)=>sum+items.length,0);
  }
  return topology;
}
async function state(db,plan,tx){
  const parent=await tx.get(db.doc(plan.parentPath)),children=new Map(),counts={};
  for(const name of Object.keys(plan.counts)){
    const docs=await tx.get(db.collection(`${plan.parentPath}/${name}`));
    counts[name]=docs.size;
    for(const doc of docs.docs)children.set(doc.ref.path,doc.data());
  }
  return {parent:parent.exists?parent.data():null,children,counts};
}
function inspect(plan,manifest,current,topology){
  const {unexpectedCollections,existingCollectionCount,nestedCollections}=topology;
  const missingParentDocumentReferences=Object.entries(topology.listedDocuments).reduce((sum,[name,count])=>sum+Math.max(0,count-(current.counts[name]||0)),0);
  const exists=current.parent!==null;
  const allChildren=current.children.size===plan.documents.length&&plan.documents.every(d=>current.children.has(d.path));
  let actualContentSha256=null,actualManifestSha256=null,referenceIntegrity='incomplete';
  if(allChildren){
    const collections={};
    for(const [name,items]of Object.entries(manifest.collections))collections[name]=items.map(({id})=>({id,...current.children.get(`${plan.parentPath}/${name}/${id}`)}));
    actualContentSha256=sha(collections);
    if(exists){const {manifestSha256,...metadata}=current.parent;actualManifestSha256=sha({catalogVersion:VERSION,metadata,collections});}
    try{for(const period of ['morning','afternoon'])validateSchedule(requestFor(collections,'2026-12-07',period),collections);referenceIntegrity='verified';}
    catch{referenceIntegrity='failed';}
  }
  const metadataMatches=exists&&isDeepStrictEqual(current.parent,plan.metadata);
  const childrenMatch=allChildren&&plan.documents.every(d=>isDeepStrictEqual(current.children.get(d.path),d.data));
  const contentHashMatches=actualContentSha256===plan.metadata.fixture.contentSha256;
  const manifestHashMatches=actualManifestSha256===plan.manifestSha256;
  const declaredManifestHashMatches=current.parent?.manifestSha256===plan.manifestSha256;
  const declaredContentHashMatches=current.parent?.fixture?.contentSha256===plan.metadata.fixture.contentSha256;
  return {parentExists:exists,metadataDocuments:exists?1:0,childDocuments:current.children.size,counts:current.counts,
    unexpectedCollections,existingCollectionCount,nestedCollections,missingParentDocumentReferences,
    metadataMatches,contentHashMatches,manifestHashMatches,declaredManifestHashMatches,declaredContentHashMatches,actualContentSha256,actualManifestSha256,
    referenceIntegrity,verified:metadataMatches&&childrenMatch&&contentHashMatches&&manifestHashMatches&&referenceIntegrity==='verified'&&unexpectedCollections===0&&nestedCollections===0&&missingParentDocumentReferences===0};
}
async function snapshot(db,plan,manifest){
  // Collection ID enumeration is a separate read API. Operators must not edit
  // the target concurrently; parent/known children use a consistent transaction.
  const unexpected=await collectionCheck(db,plan);
  return db.runTransaction(async tx=>inspect(plan,manifest,await state(db,plan,tx),unexpected));
}
async function registerAi25(db,manifest,{apply=false,verify=false,env=process.env,confirmation,approval}={}){
  guard(db.projectId,env);
  if(db.databaseId!=='(default)')throw new Error('DATABASE_MISMATCH');
  if(apply&&verify)throw new Error('CONFLICTING_MODES');
  const production=db.projectId===PROJECT;
  if(production&&apply&&(confirmation!==PROJECT||approval!==VERSION))throw new Error('PRODUCTION_APPROVAL_REQUIRED');
  const plan=makePlan(manifest);
  const base={catalogVersion:plan.catalogVersion,databaseId:'(default)',counts:plan.counts,manifestSha256:plan.manifestSha256,
    expectedContentSha256:plan.metadata.fixture.contentSha256,settingsWrites:0,accountWrites:0,scheduleWrites:0,aiControlWrites:0};
  let writeAttempted=false,before;
  try{
    if(verify){
      const after=await snapshot(db,plan,manifest);
      return {...base,status:after.verified?'VERIFIED':'VERIFICATION_FAILED',before:after,after,verified:after.verified,
        createdChildDocuments:0,createdMetadataDocuments:0,writesMayHaveCommitted:false};
    }
    const unexpected=await collectionCheck(db,plan);
    const result=await db.runTransaction(async tx=>{
      const current=await state(db,plan,tx);
      before=inspect(plan,manifest,current,unexpected);
      const occupied=before.parentExists||before.childDocuments>0||before.existingCollectionCount>0;
      if(occupied){
        // Production stops even if identical. --verify is the recovery path.
        return {status:production?'BLOCKED_EXISTING_CATALOG':before.verified?'ALREADY_REGISTERED':'BLOCKED_EXISTING_DATA',createdChildDocuments:0};
      }
      if(!apply)return {status:'DRY_RUN_OK',createdChildDocuments:0};
      writeAttempted=true;
      // Only creates; every read first; all 166 writes atomic.
      for(const d of plan.documents)tx.create(db.doc(d.path),d.data);
      tx.create(db.doc(plan.parentPath),plan.metadata);
      return {status:'APPLIED',createdChildDocuments:plan.documents.length};
    });
    const after=result.status==='APPLIED'?await snapshot(db,plan,manifest):before;
    const failed=result.status==='APPLIED'&&!after.verified;
    return {...base,...result,status:failed?'POST_WRITE_VERIFICATION_FAILED':result.status,before,after,verified:after.verified,
      createdMetadataDocuments:result.status==='APPLIED'?1:0,
      ...(writeAttempted&&result.status!=='APPLIED'?{createdChildDocuments:null,createdMetadataDocuments:null}:{}),
      writesMayHaveCommitted:writeAttempted};
  }catch(error){
    // Never print credential/IAM exception messages, original data or stack.
    return {...base,status:writeAttempted?'OUTCOME_UNKNOWN':'READ_FAILED',
      errorCode:writeAttempted?'COMMIT_OR_VERIFICATION_UNCERTAIN':'READ_OR_PRECHECK_FAILED',
      before:before||null,after:null,verified:false,createdChildDocuments:writeAttempted?null:0,
      createdMetadataDocuments:writeAttempted?null:0,writesMayHaveCommitted:writeAttempted,
      recovery:'Run --verify first. Never delete, overwrite, append or automatically retry.'};
  }
}
module.exports={guard,registerAi25,PROJECT};
