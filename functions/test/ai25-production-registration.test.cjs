'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {parse}=require('../../tools/register-ai25-catalog.cjs');
const {guard,registerAi25,PROJECT}=require('../../tools/ai25_registration.cjs');
const {buildManifest,makePlan,VERSION}=require('../../tools/ai25_fixture.cjs');
if(process.env.GCLOUD_PROJECT!=='demo-senior-transport'||!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||''))throw Error('Demo loopback Emulator required');
const manifest=buildManifest(),plan=makePlan(manifest);
const approval={apply:true,confirmation:PROJECT,approval:VERSION,env:{}};
// Test-only adapter: production policy is evaluated, but every method is bound
// to a real loopback demo Firestore client. Never construct a production client.
function productionPolicyOnDemo(db,overrides={}){
  return new Proxy(db,{get(target,key){
    if(key==='projectId')return PROJECT;
    if(Object.hasOwn(overrides,key))return overrides[key];
    const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
  }});
}
async function withDemo(name,body){
  const projectId=`demo-ai25-production-${name}`,app=initializeApp({projectId},projectId),db=getFirestore(app);
  try{await body(db);}finally{await deleteApp(app);}
}
test('real project parse requires explicit catalog approval and rejects mixed targets before SDK initialization',()=>{
  const approved=['--project',PROJECT,'--apply','--confirm-project',PROJECT,'--approve-catalog',VERSION];
  assert.equal(parse(['--project',PROJECT],{}).apply,false);
  assert.equal(parse(['--project',PROJECT,'--verify'],{}).verify,true);
  assert.equal(parse(approved,{}).apply,true);
  for(const args of [
    ['--apply'],['--verify'],['--project','other'],['--project',PROJECT,'--apply'],
    ['--project',PROJECT,'--apply','--confirm-project',PROJECT],
    ['--project',PROJECT,'--apply','--confirm-project',PROJECT,'--approve-catalog','deploy-test-v2'],
    ['--project',PROJECT,'--verify','--apply'],['--project',PROJECT,'--verify','--dry-run'],
    ['--project',PROJECT,'--plan','--dry-run'],['--project',PROJECT,'--approve-catalog',VERSION],
    ['--project',PROJECT,'--database','other'],['--project',PROJECT,'--catalog-version','other'],['--force'],
  ])assert.throws(()=>parse(args,{}));
  for(const key of ['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','FIREBASE_EMULATOR_HUB',
    'FUNCTIONS_EMULATOR','FUNCTIONS_EMULATOR_HOST','FIREBASE_STORAGE_EMULATOR_HOST'])assert.throws(()=>parse(approved,{[key]:'127.0.0.1:1234'}));
  assert.throws(()=>parse(approved,{GCLOUD_PROJECT:'other'}));
  assert.throws(()=>parse(approved,{GOOGLE_CLOUD_PROJECT:'other'}));
  assert.throws(()=>parse(approved,{FIREBASE_CONFIG:'{"projectId":"other"}'}));
  assert.throws(()=>parse(approved,{FIREBASE_CONFIG:'not-json'}));
  assert.throws(()=>guard('demo-ai25',{}));
});
test('production registration scopes all writes, reports exact integrity, and stops even for an identical existing catalog',()=>withDemo('scoped',async db=>{
  const sentinels={'settings/schedules':{catalogVersion:'deploy-test-v2'},'catalogs/deploy-test-v2':{ready:true},
    'catalogs/deploy-test-v2/staff/s1':{name:'보존 직원'},'users/keep':{active:true,role:'staff',staffId:'s1'},
    'schedules/2026-12-07_morning':{version:17},'_aiControl/config':{mode:'off'},'_aiRequests/keep':{state:'failed'}};
  for(const [path,data]of Object.entries(sentinels))await db.doc(path).create(data);
  const writes=[];
  const production=productionPolicyOnDemo(db,{runTransaction:action=>db.runTransaction(tx=>action(new Proxy(tx,{
    get(target,key){
      if(['set','update','delete'].includes(key))return()=>{throw Error('Forbidden mutation');};
      if(key==='create')return(ref,data)=>{writes.push(ref.path);return target.create(ref,data);};
      const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
    },
  })))});
  const dry=await registerAi25(production,manifest,{env:{}});
  assert.equal(dry.status,'DRY_RUN_OK');assert.equal(dry.before.childDocuments,0);assert.equal(writes.length,0);
  const result=await registerAi25(production,manifest,approval);
  assert.equal(result.status,'APPLIED');assert.equal(result.createdChildDocuments,165);assert.equal(result.createdMetadataDocuments,1);
  assert.equal(new Set(writes).size,166);assert.ok(writes.every(path=>path===plan.parentPath||path.startsWith(plan.parentPath+'/')));
  assert.deepEqual(result.after.counts,{staff:25,vehicles:20,passengers:80,baseRoutes:40});
  assert.equal(result.after.referenceIntegrity,'verified');assert.equal(result.after.actualManifestSha256,plan.manifestSha256);
  assert.equal(result.after.actualContentSha256,plan.metadata.fixture.contentSha256);assert.equal(result.verified,true);
  const beforeWrites=writes.length;
  const retry=await registerAi25(production,manifest,approval);
  assert.equal(retry.status,'BLOCKED_EXISTING_CATALOG');assert.equal(retry.verified,true);assert.equal(writes.length,beforeWrites);
  const verify=await registerAi25(production,manifest,{verify:true,env:{}});
  assert.equal(verify.status,'VERIFIED');assert.equal(verify.createdChildDocuments,0);assert.equal(writes.length,beforeWrites);
  for(const [path,data]of Object.entries(sentinels))assert.deepEqual((await db.doc(path).get()).data(),data);
  await assert.rejects(registerAi25(production,manifest,{apply:true,env:{}}),/PRODUCTION_APPROVAL_REQUIRED/);
  await assert.rejects(registerAi25(productionPolicyOnDemo(db,{databaseId:'other'}),manifest,{env:{}}),/DATABASE_MISMATCH/);
  const changed=structuredClone(manifest);changed.catalogVersion='deploy-test-v2';
  await assert.rejects(registerAi25(production,changed,approval),/FIXTURE_MANIFEST_MISMATCH/);
}));
test('concurrent production registrations create once and the other stops',()=>withDemo('concurrent',async db=>{
  const production=productionPolicyOnDemo(db);
  const results=await Promise.all([registerAi25(production,manifest,approval),registerAi25(production,manifest,approval)]);
  assert.deepEqual(results.map(r=>r.status).sort(),['APPLIED','BLOCKED_EXISTING_CATALOG']);
  assert.equal((await registerAi25(production,manifest,{verify:true,env:{}})).status,'VERIFIED');
}));
test('partial, orphaned and unexpected collection data are preserved and never completed automatically',async()=>{
  for(const kind of ['parent-only','child-only','unexpected','nested-orphan'])await withDemo(kind,async db=>{
    const path=kind==='parent-only'?plan.parentPath:kind==='child-only'?plan.documents[0].path:
      kind==='nested-orphan'?`${plan.documents[0].path}/unexpected/keep`:`${plan.parentPath}/unexpected/keep`;
    const data=kind==='parent-only'?{ready:false}:kind==='child-only'?plan.documents[0].data:{keep:true};
    await db.doc(path).create(data);
    const production=productionPolicyOnDemo(db),result=await registerAi25(production,manifest,approval);
    assert.equal(result.status,'BLOCKED_EXISTING_CATALOG');assert.equal(result.createdChildDocuments,0);
    const verification=await registerAi25(production,manifest,{verify:true,env:{}});
    assert.equal(verification.status,'VERIFICATION_FAILED');assert.deepEqual((await db.doc(path).get()).data(),data);
    if(kind==='unexpected')assert.equal(verification.after.unexpectedCollections,1);
    if(kind==='nested-orphan'){
      assert.equal(verification.after.nestedCollections,1);assert.equal(verification.after.missingParentDocumentReferences,1);
      assert.equal((await db.doc(plan.parentPath).get()).exists,false);
    }
  });
});
test('verification recomputes data hashes and rejects broken references or declared metadata hashes',()=>withDemo('tamper',async db=>{
  const production=productionPolicyOnDemo(db);await registerAi25(production,manifest,approval);
  await db.doc(`${plan.documents[0].path}/unexpected/keep`).create({keep:true});
  const nested=await registerAi25(production,manifest,{verify:true,env:{}});
  assert.equal(nested.status,'VERIFICATION_FAILED');assert.equal(nested.after.nestedCollections,1);
  const route=plan.documents.find(d=>d.path.includes('/baseRoutes/')).path;
  await db.doc(route).update({staffId:'missing-staff'});
  await db.doc(plan.parentPath).update({manifestSha256:'incorrect'});
  const result=await registerAi25(production,manifest,{verify:true,env:{}});
  assert.equal(result.status,'VERIFICATION_FAILED');assert.equal(result.after.referenceIntegrity,'failed');
  assert.equal(result.after.contentHashMatches,false);assert.equal(result.after.manifestHashMatches,false);
  assert.equal(result.after.declaredManifestHashMatches,false);
  assert.equal((await registerAi25(production,manifest,approval)).status,'BLOCKED_EXISTING_CATALOG');
  assert.equal((await db.doc(route).get()).data().staffId,'missing-staff');
}));
test('transaction failure leaves no partial writes and recommends read-only verification',()=>withDemo('abort',async db=>{
  const production=productionPolicyOnDemo(db,{runTransaction:action=>db.runTransaction(async tx=>{
    await action(tx);throw Error('SECRET_EXCEPTION_MUST_NOT_PRINT');
  })});
  const failed=await registerAi25(production,manifest,approval);
  assert.equal(failed.status,'OUTCOME_UNKNOWN');assert.equal(failed.writesMayHaveCommitted,true);
  assert.ok(!JSON.stringify(failed).includes('SECRET_EXCEPTION'));
  const verification=await registerAi25(productionPolicyOnDemo(db),manifest,{verify:true,env:{}});
  assert.equal(verification.after.childDocuments,0);assert.equal(verification.after.metadataDocuments,0);
}));
test('lost acknowledgement after commit recovers with verify without duplicate writes',()=>withDemo('lost-ack',async db=>{
  const production=productionPolicyOnDemo(db,{runTransaction:async action=>{
    await db.runTransaction(action);throw Error('SIMULATED_LOST_ACK');
  }});
  const uncertain=await registerAi25(production,manifest,approval);
  assert.equal(uncertain.status,'OUTCOME_UNKNOWN');assert.equal(uncertain.createdChildDocuments,null);
  const recovered=await registerAi25(productionPolicyOnDemo(db),manifest,{verify:true,env:{}});
  assert.equal(recovered.status,'VERIFIED');assert.equal(recovered.after.childDocuments,165);
  assert.equal((await registerAi25(productionPolicyOnDemo(db),manifest,approval)).status,'BLOCKED_EXISTING_CATALOG');
}));
test('post-commit verification mismatch stops without trying to repair data',()=>withDemo('post-check',async db=>{
  let transactions=0;
  const production=productionPolicyOnDemo(db,{runTransaction:async action=>{
    const result=await db.runTransaction(action);
    if(++transactions===1)await db.doc(plan.documents[0].path).update({name:'다른 작업의 변경'});
    return result;
  }});
  const result=await registerAi25(production,manifest,approval);
  assert.equal(result.status,'POST_WRITE_VERIFICATION_FAILED');assert.equal(result.verified,false);
  assert.equal((await db.doc(plan.documents[0].path).get()).data().name,'다른 작업의 변경');
}));
test('read errors are distinct from data conflicts and never expose source error details',()=>withDemo('read-fail',async db=>{
  const production=productionPolicyOnDemo(db,{doc:()=>{throw Error('PRIVATE_ADC_OR_IAM_MESSAGE');}});
  const result=await registerAi25(production,manifest,{env:{}});
  assert.equal(result.status,'READ_FAILED');assert.equal(result.writesMayHaveCommitted,false);
  assert.ok(!JSON.stringify(result).includes('PRIVATE_ADC'));
}));
