'use strict';
// Local browser harness. It uses the real Emulator build, never Firebase production.
const {createServer}=require('node:http');
const {readFileSync,writeFileSync,mkdirSync,existsSync}=require('node:fs');
const {resolve,extname,sep}=require('node:path');
const {spawn}=require('node:child_process');
const {randomBytes}=require('node:crypto');
const {prepare,guard}=require('./prepare_operations_emulator.cjs');
const {operationsCatalog,operationRequest}=require('./operations_fixture.cjs');
const assert=require('node:assert/strict');
const delay=(ms)=>new Promise((r)=>setTimeout(r,ms));
const runLabel=process.env.OPERATIONS_RUN_LABEL||'operations';
if(!/^[a-z0-9-]+$/.test(runLabel))throw new Error('Invalid local run label');
const artifacts=resolve(__dirname,`../.local-tools/${runLabel}`);

async function main() {
  guard(); mkdirSync(artifacts,{recursive:true});
  let stage='prepare';
  const passwordFile=resolve(artifacts,'local-emulator-password.txt');
  const password=process.env.EMULATOR_USER_PASSWORD||(existsSync(passwordFile)?readFileSync(passwordFile,'utf8'):randomBytes(24).toString('base64url'));
  const environment=await prepare(password);
  writeFileSync(passwordFile,password);
  const root=resolve(__dirname,'../build/web');
  const compiled=readFileSync(resolve(root,'main.dart.js'),'utf8');
  if (!compiled.includes('demo-senior-transport')||!compiled.includes('demo-emulator-key')) throw new Error('Emulator Web build required');
  const mime={'.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.html':'text/html','.css':'text/css','.png':'image/png'};
  const server=createServer((req,res)=>{
    const filename=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname));
    if (filename!==root&&!filename.startsWith(root+sep)) {res.writeHead(403);res.end();return;}
    try {
      const file=filename===root?resolve(root,'index.html'):filename;
      let data=readFileSync(file);
      if (file.endsWith('flutter_bootstrap.js')) data=Buffer.from(data.toString().replace('_flutter.loader.load();','_flutter.loader.load({config:{canvasKitBaseUrl:"/canvaskit/"}});'));
      res.writeHead(200,{'Content-Type':mime[extname(file)]||'application/octet-stream','Cache-Control':'no-store'});res.end(data);
    } catch(_) {res.writeHead(404);res.end();}
  });
  await new Promise((r)=>server.listen(8765,'127.0.0.1',r));
  const chrome=spawn(process.env.OPERATIONS_CHROME||'C:/Program Files/Google/Chrome/Application/chrome.exe',[
    '--headless=new','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-sync',
    '--enable-unsafe-swiftshader','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9223',
    `--user-data-dir=${resolve(artifacts,'chrome-profile')}`,'--window-size=1440,1000','about:blank',
  ],{windowsHide:true,stdio:'ignore'});
  let ws; let request=0; const pending=new Map(); const exceptions=[]; const network=[];
  const call=(method,params={})=>new Promise((yes,no)=>{
    const id=++request; pending.set(id,{yes,no});ws.send(JSON.stringify({id,method,params}));
    setTimeout(()=>{if(pending.delete(id))no(new Error(`CDP timeout: ${method}`));},20000).unref();
  });
  const evaluate=async(expression)=>(await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true})).result.value;
  const hasText=(text)=>evaluate(`(document.body.textContent+' '+Array.from(document.querySelectorAll('[aria-label]')).map(e=>e.getAttribute('aria-label')).join(' ')).replace(/\\s+/g,' ').includes(${JSON.stringify(text)})`);
  async function click(text,contains=false) {
    await waitFor(()=>evaluate(`Array.from(document.querySelectorAll('[role="button"],[role="menuitem"],[role="checkbox"],button')).some(e=>{const t=(e.getAttribute('aria-label')||e.innerText).trim();return ${contains?'t.includes':'t==='}${contains?'(':''}${JSON.stringify(text)}${contains?')':''};})`),15000);
    const rect=await evaluate(`(()=>{const e=Array.from(document.querySelectorAll('[role="button"],[role="menuitem"],[role="checkbox"],button')).find(e=>{const t=(e.getAttribute('aria-label')||e.innerText).trim();return ${contains?'t.includes':'t==='}${contains?'(':''}${JSON.stringify(text)}${contains?')':''};});if(!e)return null;const r=e.getBoundingClientRect();const footer=(e.getAttribute('aria-label')||e.innerText).includes('전체 직원 변경 검토·확정');return {x:r.x+r.width/2,y:r.y+(footer?Math.min(10,r.height/2):r.height/2)};})()`);
    if(!rect)throw new Error(`Button not found: ${text}`);
    await call('Input.dispatchMouseEvent',{type:'mousePressed',...rect,button:'left',clickCount:1});
    await call('Input.dispatchMouseEvent',{type:'mouseReleased',...rect,button:'left',clickCount:1});
    await delay(350);
  }
  async function fill(label,text) {
    const rect=await evaluate(`(()=>{const e=Array.from(document.querySelectorAll('input,textarea')).find(e=>e.getAttribute('aria-label')===${JSON.stringify(label)});if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);
    if(!rect)throw new Error(`Field not found: ${label}`);
    await call('Input.dispatchMouseEvent',{type:'mousePressed',...rect,button:'left',clickCount:1});
    await call('Input.dispatchMouseEvent',{type:'mouseReleased',...rect,button:'left',clickCount:1});
    await delay(120);
    await call('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
    await call('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
    await call('Input.insertText',{text});
    await delay(120);
    await waitFor(()=>evaluate(`Array.from(document.querySelectorAll('input,textarea')).some(e=>e.getAttribute('aria-label')===${JSON.stringify(label)}&&e.value===${JSON.stringify(text)})`),5000);
  }
  async function waitFor(fn,timeout=30000) {
    const start=Date.now(); while(Date.now()-start<timeout) {if(await fn())return;await delay(150);} throw new Error(`Wait failed at ${stage}`);
  }
  async function screenshot(name) {
    const data=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
    writeFileSync(resolve(artifacts,`${name}.png`),Buffer.from(data.data,'base64'));
  }
  try {
    stage='start-browser';
    await waitFor(async()=>{try{return (await fetch('http://127.0.0.1:9223/json/version')).ok;}catch(_){return false;}});
    const page=await(await fetch('http://127.0.0.1:9223/json/new?about:blank',{method:'PUT'})).json();
    ws=new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((r)=>ws.addEventListener('open',r,{once:true}));
    ws.addEventListener('message',(event)=>{
      const data=JSON.parse(event.data);
      if(data.id&&pending.has(data.id)) {const {yes,no}=pending.get(data.id);pending.delete(data.id);data.error?no(new Error(data.error.message)):yes(data.result);}
      if(data.method==='Runtime.exceptionThrown')exceptions.push(data.params.exceptionDetails.text);
      if(data.method==='Network.requestWillBeSent')network.push(data.params.request.url.split('?')[0]);
    });
    await call('Page.enable');await call('Runtime.enable');await call('Network.enable');await call('Performance.enable');
    await call('Network.setBlockedURLs',{urls:['*://firestore.googleapis.com/*','*://identitytoolkit.googleapis.com/*','*://securetoken.googleapis.com/*','*://*.cloudfunctions.net/*','*://*.run.app/*']});
    await call('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
    await call('Emulation.setTimezoneOverride',{timezoneId:'America/Los_Angeles'});
    await call('Storage.clearDataForOrigin',{origin:'http://127.0.0.1:8765',storageTypes:'all'});
    stage='load-login';await call('Page.navigate',{url:'http://127.0.0.1:8765/'});
    await waitFor(()=>evaluate("!!document.querySelector('flt-semantics-placeholder')"),60000);
    await evaluate("document.querySelector('flt-semantics-placeholder').click()");
    await delay(1500);
    stage='admin-login';
    await fill('이메일',environment.accounts.find((a)=>a.role==='admin').email);
    await fill('비밀번호',password);
    await click('로그인');
    await waitFor(()=>hasText('관리자 화면'));
    await delay(1000);
    // Keep the SDK's Emulator warning visible; only let automated clicks reach
    // the application's fixed footer beneath this development-only overlay.
    await evaluate("Array.from(document.querySelectorAll('p')).filter(e=>e.textContent.includes('Running in emulator mode')).forEach(e=>e.style.pointerEvents='none')");
    const steps=[];
    const mark=(name,start)=>steps.push({name,elapsedMs:Math.round(performance.now()-start)});
    const initialLabel=await evaluate("Array.from(document.querySelectorAll('[role=button]')).map(e=>e.innerText).find(t=>/오늘|내일|년/.test(t)&&/오전|오후/.test(t))");
    const wall=new Date(Date.now()+9*3600000);
    const minute=wall.getUTCHours()*60+wall.getUTCMinutes();
    const next=minute>=1140;
    const expectedDate=new Date(Date.UTC(wall.getUTCFullYear(),wall.getUTCMonth(),wall.getUTCDate()+(next?1:0)));
    const expectedLabel=`${next?'내일':'오늘'} · ${expectedDate.getUTCMonth()+1}월 ${expectedDate.getUTCDate()}일 (${['일','월','화','수','목','금','토'][expectedDate.getUTCDay()]}) · ${minute>=570&&!next?'오후':'오전'}`;
    assert.equal(initialLabel,expectedLabel,'Seoul selection must work with Los Angeles browser timezone');
    const targetDate=expectedDate.toISOString().slice(0,10);
    stage='manual-and-current';
    await click(next?'이전 날짜':'다음 날짜');await click('오후');
    await waitFor(()=>hasText('오후 · 근무 가능'));
    await click('전체 배정 현황');await waitFor(()=>evaluate("!!document.querySelector('input[aria-label=\"직원·이용자 이름 검색\"]')"));
    await screenshot('afternoon-absence-exclusion');await click('닫기');
    await click('현재 일정');await waitFor(()=>hasText(expectedLabel));
    await click('오전'); await waitFor(()=>hasText('오전 · 근무 가능'));
    if(process.env.OPERATIONS_CHECK_COURSE_TRANSFER==='true') {
      // A-2 uses the existing reserve s3. Friday is its baseline day off;
      // choose one of the already seeded dates without changing that baseline.
      const date=new Date(`${environment.today}T00:00:00Z`).getUTCDay()===5?environment.tomorrow:environment.today;
      if(date!==targetDate)await click(date>targetDate?'다음 날짜':'이전 날짜');
      await click('오전');await waitFor(()=>hasText('오전 · 근무 가능'));
      stage='a2-source';await fill('직원 이름 검색','김다정');await click('김다정 근무 가능 · 1개 코스 배정');
      const token=async(staffId)=>{
        const account=environment.accounts.find((a)=>staffId?a.staffId===staffId:a.role==='admin');
        const response=await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:account.email,password,returnSecureToken:true})});
        assert.equal(response.status,200);return (await response.json()).idToken;
      };
      const adminToken=await token();
      const read=async(path,bearer=adminToken)=>{
        const response=await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-senior-transport/databases/(default)/documents/${path}`,{headers:{Authorization:`Bearer ${bearer}`}});
        return {status:response.status,body:await response.json()};
      };
      const morningPath=`schedules/${date}_morning`;
      const original=await read(morningPath);assert.equal(original.status,200);assert.equal(Number(original.body.fields.version.integerValue),1);
      const otherPeriod=await read(`schedules/${date}_afternoon`);
      const otherDate=await read(`schedules/${date===environment.today?environment.tomorrow:environment.today}_morning`);
      stage='a2-absence';await click('날짜별 결근 등록·취소');await click('종일');await click('결근 등록');
      await waitFor(()=>hasText('재배정 필요'));await delay(1200);await screenshot('a2-unresolved');
      stage='a2-transfer';await click('코스 전체 재배정');await fill('코스 인계 직원 이름 검색','이온유');await screenshot('a2-occupied-target');
      await fill('코스 인계 직원 이름 검색','박여유');await screenshot('a2-eligible-target');await click('박여유',true);
      await waitFor(()=>hasText('재배정 초안 반영'));await screenshot('a2-draft');
      const beforePublish=await read(morningPath);assert.deepEqual(beforePublish.body,original.body,'draft must not write server schedule');
      await waitFor(async()=>!(await hasText('재배정 초안 반영')));
      stage='a2-confirm';await click('전체 직원 변경 검토·확정');await waitFor(()=>hasText('Firestore에 확정 저장'));await screenshot('a2-summary');
      await click('Firestore에 확정 저장');await waitFor(()=>hasText('확정 완료 · v2'),60000);
      const saved=await read(morningPath);assert.equal(Number(saved.body.fields.version.integerValue),2);
      const expected=structuredClone(original.body.fields.routes);
      expected.arrayValue.values[0].mapValue.fields.staffId={stringValue:'s3'};
      assert.deepEqual(saved.body.fields.routes,expected,'owner changes; vehicle, every stop, order and estimates stay identical');
      assert.deepEqual((await read(`schedules/${date}_afternoon`)).body,otherPeriod.body);
      assert.deepEqual((await read(`schedules/${date===environment.today?environment.tomorrow:environment.today}_morning`)).body,otherDate.body);
      assert.equal((await read(`staffSchedules/s1/days/${date}_morning`)).status,404);
      const replacementToken=await token('s3');
      const own=await read(`staffSchedules/s3/days/${date}_morning`,replacementToken);assert.equal(own.status,200);
      assert.deepEqual(own.body.fields.routes.arrayValue.values,[expected.arrayValue.values[0]]);
      assert.equal((await read(`staffSchedules/s2/days/${date}_morning`,replacementToken)).status,403);
      stage='a2-staff';await click('로그아웃');await waitFor(()=>hasText('로그인'));
      await fill('이메일',environment.accounts.find((a)=>a.staffId==='s3').email);await fill('비밀번호',password);await click('로그인');await waitFor(()=>hasText('직원 화면'));
      const currentDate=expectedDate.toISOString().slice(0,10);
      if(date!==currentDate)await click(date>currentDate?'다음 날짜':'이전 날짜');await click('오전');
      await waitFor(()=>hasText('박여유님의 오전 송영 일정'));await waitFor(()=>hasText('최신 확정 일정 · v2'));await screenshot('a2-staff-desktop');
      await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});await delay(500);await screenshot('a2-staff-mobile');
      const unexpected=network.filter((url)=>/^https?:\/\/(firestore|identitytoolkit|securetoken)\.googleapis\.com/.test(url)||/https?:\/\/[^/]+\.(cloudfunctions\.net|run\.app)/.test(url));
      assert.equal(unexpected.length,0);assert.equal(exceptions.length,0);
      const report={stage:'COMPLETE',scenario:'A-2 whole course',date,period:'morning',source:'s1',target:'s3',version:2,environment:{...environment,accounts:environment.accounts.length},exceptions,unexpectedRemoteFirebaseRequests:unexpected.length,verified:['absence','candidate search','occupied target display','draft-only','confirmation summary','identical stops/order/vehicle/estimates','atomic old/new staff documents','other date and period unchanged','staff-own read and other-staff denial','staff desktop/mobile'],screenshots:`.local-tools/${runLabel}/`};
      writeFileSync(resolve(artifacts,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));return;
    }
    if(process.env.OPERATIONS_CHECK_ABSENCE==='true') {
      stage='staff-absence-register';const started=performance.now();
      await fill('직원 이름 검색','가상 직원 4');await click('가상 직원 4 근무 가능 · 1개 코스 배정');await fill('직원 이름 검색','');
      await click('날짜별 결근 등록·취소');await click('종일');await click('결근 등록');
      await waitFor(()=>hasText('재배정 필요'));
      await screenshot('absence-registered');
      await click('전체 배정 현황');await waitFor(()=>hasText('결근 · 재배정 필요'));
      await screenshot('absence-overview');await click('닫기');
      stage='staff-absence-refresh';await call('Page.reload',{ignoreCache:true});
      await waitFor(()=>evaluate("!!document.querySelector('flt-semantics-placeholder')"),60000);
      await evaluate("document.querySelector('flt-semantics-placeholder').click()");
      await waitFor(()=>hasText('관리자 화면'));await click('오전');
      await waitFor(()=>hasText('결근 · 1개 코스 배정 · 재배정 필요'));
      await screenshot('absence-after-refresh');
      stage='staff-absence-own-view';await click('로그아웃');await waitFor(()=>hasText('로그인'));
      await fill('이메일',environment.accounts.find((a)=>a.staffId==='s4').email);await fill('비밀번호',password);await click('로그인');
      await waitFor(()=>hasText('직원 화면'));await click('오전');await waitFor(()=>hasText('결근으로 재배정 필요'));
      await screenshot('absence-staff-warning');
      assert.equal(await hasText('날짜별 결근 등록·취소'),false);
      await click('로그아웃');await waitFor(()=>hasText('로그인'));
      await fill('이메일',environment.accounts.find((a)=>a.role==='admin').email);await fill('비밀번호',password);await click('로그인');
      await waitFor(()=>hasText('관리자 화면'));await click('오전');await waitFor(()=>hasText('재배정 필요'));
      stage='staff-absence-cancel';await click('날짜별 결근 등록·취소');await click('종일');await click('결근 취소');
      await waitFor(()=>hasText('오전 · 근무 가능'));assert.equal(await hasText('새 확정 전에는 정상 운행 일정이 아닙니다.'),false);
      // Firestore's listener can deliver the new status before the Callable
      // acknowledgement releases the editor's intentional interaction lock.
      await delay(1200);
      mark('absence-register-refresh-staff-read-cancel',started);
    }
    stage='overview';let timer=performance.now();
    await click('전체 배정 현황');await waitFor(()=>evaluate("!!document.querySelector('input[aria-label=\"직원·이용자 이름 검색\"]')"));mark('overview-open',timer);
    await screenshot('overview-desktop');
    stage='staff-search';timer=performance.now();
    await fill('직원·이용자 이름 검색','가상 직원 20');await waitFor(()=>hasText('가상 20코스'));mark('overview-staff-search',timer);
    await screenshot('overview-filtered');await click('닫기');
    stage='passenger-search';timer=performance.now();
    await click('이용자 찾기');await waitFor(()=>hasText('이용자 찾기'));
    await fill('직원·이용자 이름 검색','가상 이용자 80');await waitFor(()=>hasText('가상 직원 20 · 가상 20코스'));mark('passenger-search',timer);
    await screenshot('passenger-search');await click('가상 이용자 80',true);
    await waitFor(()=>hasText('가상 직원 20님의 송영 일정'));await screenshot('detail-20');
    stage='staff-list-search';timer=performance.now();
    await fill('직원 이름 검색','김다정');await click('김다정 근무 가능 · 1개 코스 배정');
    await waitFor(()=>hasText('김다정님의 송영 일정'));mark('staff-list-search',timer);
    stage='visit-edit';
    await click('1 가상 어르신 A',true);await delay(200);await click('시각 수정');
    await waitFor(()=>hasText('예상 방문'));await fill('예상 방문','08:54');await click('적용');
    await waitFor(()=>hasText('예상 08:54'));
    stage='reassignment-menu';await click('재배정 →',true);await delay(300);
    await fill('재배정 직원 이름 검색','가상 직원 4');
    await click('근무 가능만');await click('정원 여유만');await screenshot('reassignment-targets');
    assert.equal(await hasText('현재 5/6명 · 이동 후 6명'),true);
    await click('가상 직원 4 · 가상 4코스',true);
    stage='absence-edit';
    await click('1 가상 어르신 B',true);await click('결석');
    stage='confirm';timer=performance.now();
    await click('전체 직원 변경 검토·확정');await waitFor(()=>hasText('Firestore에 확정 저장'));
    await screenshot('confirm-all-staff');await click('Firestore에 확정 저장');
    await waitFor(()=>hasText('확정 완료 · v2'),60000);mark('confirm-firestore',timer);
    await screenshot('confirmed');
    stage='staff-login';await click('로그아웃');await waitFor(()=>hasText('로그인'));
    await fill('이메일',environment.accounts.find((a)=>a.staffId==='s4').email);await fill('비밀번호',password);await click('로그인');
    await waitFor(()=>hasText('직원 화면'));await click('오전');
    await waitFor(()=>hasText('가상 직원 4님의 오전 송영 일정'));await screenshot('staff-desktop');
    await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});await delay(500);
    await screenshot('staff-mobile');
    await call('Input.dispatchMouseEvent',{type:'mouseWheel',x:200,y:700,deltaY:800,deltaX:0});await delay(500);
    await screenshot('staff-mobile-scrolled');
    stage='rules-and-server';
    const signIn=async(account)=>{
      const response=await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator`,{
        method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:account.email,password,returnSecureToken:true})});
      assert.equal(response.status,200);return (await response.json()).idToken;
    };
    const staffToken=await signIn(environment.accounts.find((a)=>a.staffId==='s4'));
    const adminToken=await signIn(environment.accounts.find((a)=>a.role==='admin'));
    const firestore=`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-senior-transport/databases/(default)/documents/`;
    const read=async(path,token)=>(await fetch(firestore+path,{headers:{Authorization:`Bearer ${token}`}}));
    const own=await read(`staffSchedules/s4/days/${targetDate}_morning`,staffToken);assert.equal(own.status,200);
    const ownData=await own.json();
    assert.equal(ownData.fields.routes.arrayValue.values[0].mapValue.fields.passengerIds.arrayValue.values.some((v)=>v.stringValue==='p1'),true);
    assert.equal((await read(`staffSchedules/s1/days/${targetDate}_morning`,staffToken)).status,403);
    assert.equal((await read(`schedules/${targetDate}_morning`,staffToken)).status,403);
    const full=await (await read(`schedules/${targetDate}_morning`,adminToken)).json();
    assert.equal(Number(full.fields.version.integerValue),2);
    assert.equal(full.fields.absentIds.arrayValue.values.some((v)=>v.stringValue==='p2'),true);
    const missing=operationRequest(operationsCatalog(),targetDate,'morning',environment.version,require('node:crypto').randomUUID(),2);
    missing.routes.at(-1).passengerIds.pop();
    delete missing.routes.at(-1).estimatedVisitMinutes.p80;
    const invoke=async(token)=>{
      const response=await fetch('http://127.0.0.1:5001/demo-senior-transport/asia-northeast3/confirmSchedule',{
        method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify({data:missing})});return response.json();
    };
    assert.equal((await invoke(adminToken)).error.status,'INVALID_ARGUMENT');
    assert.equal((await invoke(staffToken)).error.status,'PERMISSION_DENIED');
    const after=await (await read(`schedules/${targetDate}_morning`,adminToken)).json();assert.equal(Number(after.fields.version.integerValue),2);
    stage='admin-mobile';await click('로그아웃');await waitFor(()=>hasText('로그인'));
    await fill('이메일',environment.accounts.find((a)=>a.role==='admin').email);await fill('비밀번호',password);await click('로그인');
    await waitFor(()=>hasText('관리자 화면'));await screenshot('admin-mobile-list');
    await click('이용자 찾기');await fill('직원·이용자 이름 검색','가상 이용자 80');await screenshot('admin-mobile-search');
    await click('가상 이용자 80',true);await waitFor(()=>hasText('가상 직원 20님의 송영 일정'));await screenshot('admin-mobile-detail');
    const metrics=await call('Performance.getMetrics');
    const unexpected=network.filter((url)=>/^(https?:\/\/)(firestore|identitytoolkit|securetoken)\.googleapis\.com/.test(url)||/https?:\/\/[^/]+\.(cloudfunctions\.net|run\.app)/.test(url));
    assert.equal(unexpected.length,0);
    stage='COMPLETE';
    writeFileSync(resolve(artifacts,'dom-inspect.json'),JSON.stringify(await evaluate("Array.from(document.querySelectorAll('[role],input,textarea')).map(e=>({tag:e.tagName,role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.innerText,type:e.getAttribute('type')}))"),null,2));
    const report={stage,initialLabel,browserTimezone:'America/Los_Angeles',targetDate,steps,
      environment:{...environment,accounts:environment.accounts.length},exceptions,unexpectedRemoteFirebaseRequests:unexpected.length,
      jsHeapUsedMiB:Math.round(metrics.metrics.find((m)=>m.name==='JSHeapUsedSize').value/1048576*10)/10,
      screenshots:`.local-tools/${runLabel}/`,timingNote:'Includes 350ms post-click and 120ms input waits; local headless observation, not a production benchmark.'};
    writeFileSync(resolve(artifacts,'report.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify(report,null,2));
  } catch(error) {
    writeFileSync(resolve(artifacts,'failure-network-paths.json'),JSON.stringify(network,null,2));
    if(ws?.readyState===1) {try{
      writeFileSync(resolve(artifacts,`failure-${stage}-dom.json`),JSON.stringify(await evaluate("Array.from(document.querySelectorAll('[role],input,textarea')).map(e=>({role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.textContent}))"),null,2));
      await screenshot(`failure-${stage}`);
    }catch(_){}}
    console.error(JSON.stringify({status:'FAILED',stage,error:error.message,exceptions}));process.exitCode=1;
  } finally {
    if(ws?.readyState===1) {try{await call('Browser.close');}catch(_){} ws.close();}
    chrome.kill();server.close();
  }
}
if(require.main===module)main().catch(()=>{console.error('Local browser setup failed; no credentials printed.');process.exitCode=1;});
