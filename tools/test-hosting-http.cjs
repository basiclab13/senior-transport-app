'use strict';
// HTTP bytes only: never executes the Firebase-connected JavaScript bundle.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {createHash}=require('node:crypto');
const hash=(value)=>createHash('sha256').update(value).digest('hex');

async function main() {
  if(process.env.GCLOUD_PROJECT!=='demo-senior-transport')throw new Error('Demo Hosting Emulator required');
  const origin='http://127.0.0.1:5000';
  const root=path.resolve(__dirname,'../build/web');
  const index=fs.readFileSync(path.join(root,'index.html'));
  const checks=[];
  for(const route of ['/','/index.html','/schedule/2026-11-14?period=morning','/schedule/2026-11-14?period=morning','/functions/index.js','/.last_build_id','/main.dart.js.map']) {
    const response=await fetch(origin+route,{headers:{'Cache-Control':'no-cache'}});
    assert.equal(response.status,200,route);
    console.log(JSON.stringify({route,status:response.status,contentType:response.headers.get('content-type'),cacheControl:response.headers.get('cache-control'),noSniff:response.headers.get('x-content-type-options')}));
    assert.match(response.headers.get('content-type')||'',/text\/html/,`${route}: content-type`);
    assert.match(response.headers.get('cache-control')||'',/no-cache/,`${route}: cache-control`);
    assert.equal(response.headers.get('x-content-type-options'),'nosniff');
    assert.equal(hash(Buffer.from(await response.arrayBuffer())),hash(index),route);
    checks.push(route);
  }
  for(const asset of ['main.dart.js','flutter_bootstrap.js','manifest.json']) {
    const response=await fetch(`${origin}/${asset}`);
    assert.equal(response.status,200);
    assert.match(response.headers.get('cache-control'),/no-cache/);
    assert.equal(hash(Buffer.from(await response.arrayBuffer())),hash(fs.readFileSync(path.join(root,asset))));
    if(asset.endsWith('.js'))assert.match(response.headers.get('content-type'),/javascript/);
    checks.push(`/${asset}`);
  }
  console.log(JSON.stringify({status:'PASSED',origin,checks,executedApplicationJavaScript:false,remoteFirebaseRequests:0}));
}
if(require.main===module)main().catch(error=>{console.error(error.message);process.exitCode=1;});
