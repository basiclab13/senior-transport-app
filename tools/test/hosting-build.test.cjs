'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {inspectBuild,verify}=require('../verify-hosting-build.cjs');

function fixture(t) {
  const prefix=path.join(path.resolve(os.tmpdir()),'transport-hosting-');
  const root=fs.mkdtempSync(prefix);
  const web=path.join(root,'build','web');fs.mkdirSync(web,{recursive:true});
  fs.writeFileSync(path.join(root,'firebase.json'),JSON.stringify({hosting:{public:'build/web'}}));
  for(const [name,content] of Object.entries({'index.html':'<base href="/">','main.dart.js':'senior-transport-app','flutter_bootstrap.js':'bootstrap','flutter.js':'loader','manifest.json':'{}','version.json':'{}'}))fs.writeFileSync(path.join(web,name),content);
  t.after(()=>{
    const target=path.resolve(root);
    assert.ok(target.startsWith(prefix),'temporary cleanup must stay inside the named test directory');
    fs.rmSync(target,{recursive:true,force:true});
  });
  return {root,web};
}

test('unrecorded, changed or differently configured builds cannot pass the predeploy check',t=>{
  const {root,web}=fixture(t);
  assert.throws(()=>verify(root,{env:{}}),/BUILD_RECEIPT_MISSING/);
  const original=verify(root,{record:true,env:{}});
  assert.equal(verify(root,{env:{}}).fingerprint,original.fingerprint);
  fs.appendFileSync(path.join(web,'main.dart.js'),'changed');
  assert.throws(()=>verify(root,{env:{}}),/BUILD_CHANGED/);
  verify(root,{record:true,env:{}});
  fs.writeFileSync(path.join(root,'firebase.json'),JSON.stringify({hosting:{public:'build/web',headers:[]}}));
  assert.throws(()=>verify(root,{env:{}}),/BUILD_CHANGED/);
});

test('Emulator bundles, debug bundles and an incorrect deploy project are rejected',t=>{
  const {root,web}=fixture(t);
  assert.throws(()=>verify(root,{record:true,env:{GCLOUD_PROJECT:'other-project'}}),/DEPLOY_PROJECT/);
  assert.throws(()=>verify(root,{record:true,env:{FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080'}}),/EMULATOR_ENVIRONMENT/);
  for(const marker of ['demo-emulator-key','demo-senior-transport','[staff-availability]','[firebase] project=']) {
    fs.writeFileSync(path.join(web,'main.dart.js'),`senior-transport-app ${marker}`);
    assert.throws(()=>inspectBuild(root),/MISMATCH|DEBUG_BUILD/);
  }
});

test('private keys and credentials are detected even with an arbitrary filename',t=>{
  const {root,web}=fixture(t);
  for(const content of [{type:'service_account',project_id:'fictional'}, {nested:{refresh_token:'fictional-token'}}, {private_key:'fictional-key'},{client_secret:'fictional-secret'}]) {
    fs.writeFileSync(path.join(web,'innocent.json'),JSON.stringify(content));
    assert.throws(()=>inspectBuild(root),/CREDENTIAL_CONTENT/);
  }
  fs.unlinkSync(path.join(web,'innocent.json'));
  fs.writeFileSync(path.join(web,'innocent.txt'),'-----BEGIN PRIVATE KEY-----\nfictional test marker');
  assert.throws(()=>inspectBuild(root),/PRIVATE_KEY_CONTENT/);
});

test('credential filenames and source folders are rejected; Firebase Web config identifiers remain allowed',t=>{
  const {root,web}=fixture(t);
  fs.writeFileSync(path.join(web,'public-config.json'),JSON.stringify({projectId:'senior-transport-app',apiKey:'fictional-public-web-identifier'}));
  assert.doesNotThrow(()=>inspectBuild(root));
  for(const name of ['.env','credentials.json','test-service-account.json','private.pem']) {
    fs.writeFileSync(path.join(web,name),'fictional');
    assert.throws(()=>inspectBuild(root),/PRIVATE_OR_SOURCE/);
    fs.unlinkSync(path.join(web,name));
  }
  fs.mkdirSync(path.join(web,'functions'));fs.writeFileSync(path.join(web,'functions','index.js'),'fictional');
  assert.throws(()=>inspectBuild(root),/SOURCE_DIRECTORY/);
});

test('incomplete builds and non-root base paths are rejected',t=>{
  const {root,web}=fixture(t);
  fs.writeFileSync(path.join(web,'index.html'),'<base href="/other/">');
  assert.throws(()=>inspectBuild(root),/ROOT_BASE_HREF/);
  fs.writeFileSync(path.join(web,'index.html'),'<base href="/">');
  fs.unlinkSync(path.join(web,'flutter_bootstrap.js'));
  assert.throws(()=>inspectBuild(root),/INCOMPLETE_FLUTTER/);
});
