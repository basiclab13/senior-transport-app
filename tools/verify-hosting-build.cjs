'use strict';
// Local files only. This module never authenticates or connects to Firebase.
const fs=require('node:fs');
const path=require('node:path');
const {createHash}=require('node:crypto');
const PROJECT='senior-transport-app';
const digest=(value)=>createHash('sha256').update(value).digest('hex');
const fail=(code)=>{throw new Error(code);};

function inspectBuild(workspace) {
  const config=JSON.parse(fs.readFileSync(path.join(workspace,'firebase.json'),'utf8').replace(/^\uFEFF/,''));
  if(config.hosting?.public!=='build/web')fail('UNEXPECTED_PUBLIC_DIRECTORY');
  const root=path.join(workspace,'build','web');
  if(!fs.existsSync(root))fail('BUILD_MISSING');
  const files=[];
  function walk(folder) {
    if(fs.lstatSync(folder).isSymbolicLink())fail('SYMLINK_IN_PUBLIC_DIRECTORY');
    for(const entry of fs.readdirSync(folder,{withFileTypes:true})) {
      const full=path.join(folder,entry.name);
      const relative=path.relative(root,full).split(path.sep).join('/');
      if(entry.isSymbolicLink())fail('SYMLINK_IN_PUBLIC_DIRECTORY');
      if(entry.isDirectory()) {
        if(['functions','tools','docs','lib','test','node_modules','.git'].includes(relative.split('/')[0]))fail('SOURCE_DIRECTORY_IN_BUILD');
        walk(full);continue;
      }
      if(!entry.isFile())fail('UNEXPECTED_PUBLIC_ENTRY');
      if(/(?:^|\/)(?:\.env(?:\..*)?|[^/]*(?:service[-_]?account|firebase-adminsdk|credentials)[^/]*\.json)$|\.(?:pem|key|p12|pfx|dart|cjs|ps1)$/i.test(relative))fail('PRIVATE_OR_SOURCE_FILE_IN_BUILD');
      const data=fs.readFileSync(full);
      const text=data.toString('utf8');
      if(/-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/.test(text))fail('PRIVATE_KEY_CONTENT_IN_BUILD');
      if(entry.name.endsWith('.json')) {
        let json;
        try {json=JSON.parse(text.replace(/^\uFEFF/,''));}catch {fail('INVALID_JSON_IN_BUILD');}
        const credentials=(value)=>value&&typeof value==='object'&&(
          value.type==='service_account'||Object.entries(value).some(([key,item])=>
            (['private_key','client_secret','refresh_token','access_token'].includes(key)&&typeof item==='string'&&item.length>0)||credentials(item)));
        if(credentials(json))fail('CREDENTIAL_CONTENT_IN_BUILD');
      }
      files.push({path:relative,size:data.length,sha256:digest(data)});
    }
  }
  walk(root);
  const required=['index.html','main.dart.js','flutter_bootstrap.js','flutter.js','manifest.json','version.json'];
  if(required.some((name)=>!files.some((f)=>f.path===name)))fail('INCOMPLETE_FLUTTER_BUILD');
  const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
  if(!/<base\s+href=["']\/["']\s*\/?\s*>/i.test(html))fail('ROOT_BASE_HREF_REQUIRED');
  const bundle=fs.readFileSync(path.join(root,'main.dart.js'),'utf8');
  if(!bundle.includes(PROJECT)||bundle.includes('demo-senior-transport')||bundle.includes('demo-emulator-key'))fail('FIREBASE_PROJECT_OR_EMULATOR_MISMATCH');
  if(bundle.includes('[staff-availability]')||bundle.includes('[firebase] project='))fail('DEBUG_BUILD_REJECTED');
  files.sort((a,b)=>a.path.localeCompare(b.path));
  return {projectId:PROJECT,public:'build/web',buildMode:'release',fingerprint:digest(JSON.stringify({hosting:config.hosting,files})),fileCount:files.length,sourceMapsExcluded:files.filter((f)=>f.path.endsWith('.map')).length,files};
}

function verify(workspace,{record=false,env=process.env}={}) {
  if(env.GCLOUD_PROJECT&&env.GCLOUD_PROJECT!==PROJECT)fail('DEPLOY_PROJECT_MISMATCH');
  if(env.FIRESTORE_EMULATOR_HOST||env.FIREBASE_AUTH_EMULATOR_HOST||env.FIREBASE_EMULATOR_HUB)fail('EMULATOR_ENVIRONMENT');
  const result=inspectBuild(workspace);
  const folder=path.join(workspace,'.local-tools','hosting');
  const receipt=path.join(folder,'verified-build.json');
  if(record) {
    fs.mkdirSync(folder,{recursive:true});
    fs.writeFileSync(receipt,JSON.stringify({...result,checkedAt:new Date().toISOString()},null,2));
  } else {
    if(!fs.existsSync(receipt))fail('BUILD_RECEIPT_MISSING');
    const previous=JSON.parse(fs.readFileSync(receipt,'utf8'));
    if(previous.projectId!==PROJECT||previous.buildMode!=='release'||previous.fingerprint!==result.fingerprint)fail('BUILD_CHANGED_SINCE_VERIFICATION');
  }
  return result;
}

if(require.main===module) {
  try {
    const args=process.argv.slice(2);
    if(args.some((a)=>a!=='--record')||args.length>1)fail('UNSUPPORTED_ARGUMENT');
    const result=verify(path.resolve(__dirname,'..'),{record:args.includes('--record')});
    console.log(JSON.stringify({status:'VERIFIED',projectId:result.projectId,public:result.public,buildMode:result.buildMode,fileCount:result.fileCount,fingerprint:result.fingerprint,sourceMapsExcluded:result.sourceMapsExcluded}));
  } catch(error) {
    console.error(JSON.stringify({status:'BLOCKED',errorCode:error.message,guidance:'Run powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hosting.ps1. No Firebase changes were made.'}));process.exitCode=1;
  }
}
module.exports={inspectBuild,verify};
