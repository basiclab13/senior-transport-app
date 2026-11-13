'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {generateGemini}=require('../gemini-schedule');

test('Gemini REST adapter uses structured JSON, a header secret, and no real network in tests',async()=>{
  let calls=0;
  const result=await generateGemini({routes:[]},{apiKey:'unit-test-only',model:'gemini-3.8-flash',log:()=>{},fetchImpl:async(url,request)=>{
    calls++;
    assert.ok(!url.includes('unit-test-only'));
    assert.equal(request.headers['x-goog-api-key'],'unit-test-only');
    const body=JSON.parse(request.body);
    assert.equal(body.generationConfig.responseMimeType,'application/json');
    assert.deepEqual(body.generationConfig.responseJsonSchema.required,['routes','reasons']);
    return {ok:true,json:async()=>({candidates:[{finishReason:'STOP',content:{parts:[{thought:true,text:'not output'},{text:'{"routes":[],"reasons":["변경 없음"]}'}]}}]})};
  }});
  assert.equal(calls,1);assert.deepEqual(result,{routes:[],reasons:['변경 없음']});
});
test('missing key/model, quota, provider failure, refusal, truncated JSON and network errors are safe',async()=>{
  let calls=0;
  const noCall=async()=>{calls++;throw Error('unexpected network');};
  await assert.rejects(generateGemini({},{fetchImpl:noCall,log:()=>{}}),e=>e.code==='failed-precondition');
  await assert.rejects(generateGemini({},{apiKey:'unit-test-only',model:'../bad',fetchImpl:noCall,log:()=>{}}),e=>e.code==='failed-precondition');
  assert.equal(calls,0);
  for(const mock of [
    async()=>({ok:false,status:429}),async()=>({ok:false,status:500}),
    async()=>({ok:true,json:async()=>({promptFeedback:{blockReason:'SAFETY'}})}),
    async()=>({ok:true,json:async()=>({candidates:[{finishReason:'MAX_TOKENS'}]})}),
    async()=>({ok:true,json:async()=>({candidates:[{finishReason:'STOP',content:{parts:[{text:'not-json'}]}}]})}),
    async()=>{throw Error('unit-test-only private provider detail');},
  ])await assert.rejects(generateGemini({},{apiKey:'unit-test-only',fetchImpl:mock,log:()=>{}}),e=>
    ['unavailable','resource-exhausted'].includes(e.code)&&!e.message.includes('unit-test-only')&&!e.message.includes('private provider'));
});
test('request-scoped response enums guide Gemini without weakening server constraints or leaking raw payloads',async()=>{
  const input={routes:[{baseRouteId:'morning-a'}],availableStaffIds:['s3'],requiredPassengerIds:['p1','p3'],requiredRouteCount:1};
  const records=[];
  const invoke=async data=>generateGemini(data,{apiKey:'never-log-key',log:r=>records.push(r),fetchImpl:async(_url,request)=>{
    const body=JSON.parse(request.body),fields=body.generationConfig.responseJsonSchema.properties.routes.items.properties;
    assert.deepEqual(fields.baseRouteId.enum,['morning-a']);
    if(data.availableStaffIds.length)assert.deepEqual(fields.staffId.enum,['s3']);
    else assert.equal(fields.staffId.enum,undefined); // An empty enum is an invalid provider schema.
    if(data.requiredPassengerIds.length)assert.deepEqual(fields.passengerIds.items.enum,['p1','p3']);
    else assert.equal(fields.passengerIds.maxItems,0);
    return {ok:true,status:200,json:async()=>({candidates:[{finishReason:'STOP',content:{parts:[{text:'{"routes":[],"reasons":[]}'}]}}]})};
  }});
  await invoke(input);
  await invoke({...input,availableStaffIds:[],requiredPassengerIds:[]});
  assert.ok(!JSON.stringify(records).includes('morning-a'));
  assert.ok(!JSON.stringify(records).includes('never-log'));
});

test('diagnostics distinguish Gemini HTTP status from the Callable unavailable/503 mapping without reading error bodies',async()=>{
  for(const status of [400,403,429,503]) {
    const records=[];
    await assert.rejects(generateGemini({private:'never-log-input'},{
      apiKey:'never-log-key',log:r=>records.push(r),
      fetchImpl:async()=>({ok:false,status,json:async()=>{throw Error('must not read provider error body');}}),
    }),e=>e.code===(status===429?'resource-exhausted':'unavailable'));
    const last=records.at(-1);
    assert.equal(last.event,'failed');assert.equal(last.stage,'response-headers');
    assert.equal(last.httpStatus,status);assert.equal(last.errorType,'GEMINI_HTTP_ERROR');
    assert.equal(last.timeoutTriggered,false);assert.ok(last.elapsedMs>=0);
    assert.equal(last.timeoutMs,45000);
    assert.ok(!JSON.stringify(records).includes('never-log'));
  }
});
test('the unchanged 45-second server abort is diagnosed before headers, without waiting or real API calls',async()=>{
  const records=[];
  let configuredTimeout;
  await assert.rejects(generateGemini({},{apiKey:'never-log-key',log:r=>records.push(r),
    timeoutSignalFactory:milliseconds=>{
      configuredTimeout=milliseconds;
      return AbortSignal.abort(new DOMException('never-log-timeout-message','TimeoutError'));
    },
    fetchImpl:async(_url,{signal})=>signal.throwIfAborted(),
  }),e=>e.code==='unavailable');
  assert.equal(configuredTimeout,45000);
  const last=records.at(-1);
  assert.equal(last.stage,'request');assert.equal(last.errorType,'REQUEST_TIMEOUT');
  assert.equal(last.timeoutTriggered,true);assert.equal(last.httpStatus,null);
  assert.ok(!JSON.stringify(records).includes('never-log'));
});
test('timeout after HTTP 200 headers is a response-body timeout, even when fetch throws AbortError',async()=>{
  const records=[],controller=new AbortController();
  await assert.rejects(generateGemini({},{apiKey:'never-log-key',log:r=>records.push(r),
    timeoutSignalFactory:()=>controller.signal,
    fetchImpl:async()=>({ok:true,status:200,json:async()=>{
      controller.abort(new DOMException('never-log-reason','TimeoutError'));
      throw new DOMException('never-log-body','AbortError');
    }}),
  }),e=>e.code==='unavailable');
  const last=records.at(-1);
  assert.equal(last.stage,'response-body');assert.equal(last.httpStatus,200);
  assert.equal(last.errorType,'REQUEST_TIMEOUT');assert.equal(last.timeoutTriggered,true);
  assert.ok(!JSON.stringify(records).includes('never-log'));
});
test('network codes are allowlisted and provider JSON failures are separate from transport failures',async()=>{
  const cases=[
    {type:'NETWORK_ERROR',stage:'request',code:'ENOTFOUND',fetchImpl:async()=>{throw Object.assign(new Error('never-log-network'),{cause:{code:'ENOTFOUND'}});}},
    {type:'NETWORK_TIMEOUT',stage:'request',code:'UND_ERR_CONNECT_TIMEOUT',fetchImpl:async()=>{throw Object.assign(new Error('never-log-network'),{cause:{code:'UND_ERR_CONNECT_TIMEOUT'}});}},
    {type:'NETWORK_TIMEOUT',stage:'request',code:'ETIMEDOUT',fetchImpl:async()=>{throw Object.assign(new Error('never-log-network'),{cause:{code:'ETIMEDOUT'}});}},
    {type:'NETWORK_ERROR',stage:'request',fetchImpl:async()=>{throw Object.assign(new Error('never-log-network'),{cause:{code:'never-log-code'}});}},
    {type:'RESPONSE_JSON_ERROR',stage:'response-body',fetchImpl:async()=>({ok:true,status:200,json:async()=>{throw new SyntaxError('never-log-response');}})},
    {type:'JSON_PARSE_ERROR',stage:'proposal-json',fetchImpl:async()=>({ok:true,status:200,json:async()=>({candidates:[{finishReason:'STOP',content:{parts:[{text:'never-log-proposal'}]}}]})})},
    {type:'GEMINI_INCOMPLETE_RESPONSE',stage:'candidate',fetchImpl:async()=>({ok:true,status:200,json:async()=>({candidates:[{finishReason:'MAX_TOKENS'}]})})},
  ];
  for(const fixture of cases) {
    const records=[];
    await assert.rejects(generateGemini({},{apiKey:'never-log-key',log:r=>records.push(r),fetchImpl:fixture.fetchImpl}),e=>e.code==='unavailable');
    const last=records.at(-1);
    assert.equal(last.errorType,fixture.type);assert.equal(last.stage,fixture.stage);
    assert.equal(last.networkCode,fixture.code);assert.ok(last.elapsedMs>=0);
    assert.ok(!JSON.stringify(records).includes('never-log'));
  }
});
