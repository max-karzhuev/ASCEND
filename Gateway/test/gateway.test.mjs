import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import { publicIP, validateEndpoint, adapterRequest, callProvider, providersFromEnv, secureTransport } from '../providers.mjs';
import { createGateway, Quota } from '../server.mjs';
import { validateSession, validateGrade, sessionSchema, GatewayError } from '../schema.mjs';

const token = 'test-only-not-a-real-token-01234567890123456789';
const question = { id:'q1',kind:'numerical',prompt:'2 + 2?',options:[],answer:'4',tolerance:0,hints:['Count two pairs'],explanation:'Two plus two equals four.',topic:'Arithmetic' };
const config = {subject:'Mathematics',subtopic:'',ability:'Foundations',difficulty:'easy',count:1,mode:'practice'};
const providerConfig = {key:'test-fixture',models:['fixture-model'],version:'2023-06-01',base:'https://api.example.com/v1'};
function wrapper(provider, value) {
  const text=JSON.stringify(value);
  if (provider==='openai') return {status:'completed',output:[{content:[{type:'output_text',text}]}]};
  if (provider==='anthropic') return {stop_reason:'end_turn',content:[{type:'text',text}]};
  if (provider==='gemini') return {candidates:[{finishReason:'STOP',content:{parts:[{text}]}}]};
  return {choices:[{finish_reason:'stop',message:{content:text}}]};
}
test('rejects all private, loopback, link-local, mapped and documentation IP classes', () => {
  for (const ip of ['127.0.0.1','10.0.0.2','172.16.0.1','192.168.1.4','169.254.169.254','100.64.0.1','0.0.0.0','224.0.0.1','198.18.0.2','198.51.100.2','203.0.113.1','::1','::ffff:127.0.0.1','fc00::1','fe80::1','2001:db8::1','2002:7f00:1::']) assert.equal(publicIP(ip),false,ip);
  assert.equal(publicIP('8.8.8.8'),true); assert.equal(publicIP('2606:4700:4700::1111'),true);
});
test('custom endpoints require exact HTTPS host allowlist without credentials or redirects', () => {
  for(const url of ['http://api.example.com/v1','https://localhost/v1','https://127.0.0.1/v1','https://evil.example/v1','https://api.example.com:8443/v1','https://user:pass@api.example.com/v1','https://api.example.com/v1?target=internal']) assert.throws(()=>validateEndpoint(url,['api.example.com']));
  assert.equal(validateEndpoint('https://api.example.com/v1',['api.example.com']).hostname,'api.example.com');
});
test('transport rejects DNS answers containing a private address before opening a socket', async()=>{
  await assert.rejects(secureTransport(new URL('https://api.example.com'),{},'{}',new AbortController().signal, async()=>[{address:'8.8.8.8',family:4},{address:'10.0.0.1',family:4}]), /prohibited/);
});
test('transport cancels even when DNS resolution never returns', async()=>{
  const controller = new AbortController();
  const pending = secureTransport(new URL('https://api.example.com'),{},'{}',controller.signal,()=>new Promise(()=>{}));
  controller.abort(new Error('cancelled during DNS'));
  await assert.rejects(pending,/cancelled during DNS/);
});
test('provider adapters have distinct verified wire formats',()=>{
  const openai=adapterRequest('openai',providerConfig,'fixture-model','system',{},sessionSchema);
  assert.equal(openai.body.store,false);assert.equal(openai.body.text.format.strict,true);assert.equal(openai.url.pathname,'/v1/responses');
  const anthropic=adapterRequest('anthropic',providerConfig,'fixture-model','system',{},sessionSchema);
  assert.equal(anthropic.headers['anthropic-version'],'2023-06-01');assert.equal(anthropic.body.output_config.format.type,'json_schema');assert.equal(anthropic.body.system,'system');
  const gemini=adapterRequest('gemini',providerConfig,'fixture-model','system',{},sessionSchema);
  assert.ok(gemini.headers['x-goog-api-key']);assert.equal(gemini.body.generationConfig.responseMimeType,'application/json');assert.ok(gemini.body.systemInstruction.parts);
  const compatible=adapterRequest('compatible',providerConfig,'fixture-model','system',{},sessionSchema);
  assert.equal(compatible.url.pathname,'/v1/chat/completions');assert.equal(compatible.body.response_format.json_schema.strict,true);
});
for(const provider of ['openai','anthropic','gemini','compatible']) test(`${provider} parses a valid structured fixture`,async()=>{
  const result=await callProvider({provider,config:providerConfig,model:'fixture-model',system:'system',input:config,schema:sessionSchema,transport:async()=>({status:200,body:JSON.stringify(wrapper(provider,{questions:[question]}))})});
  assert.equal(validateSession(result,1).questions[0].answer,'4');
});
test('bounded retry happens for rate limiting but never authentication errors',async()=>{
  let count=0;
  const args={provider:'openai',config:providerConfig,model:'fixture-model',system:'s',input:{},schema:sessionSchema,delay:async()=>{}};
  await assert.rejects(callProvider({...args,transport:async()=>{count++;return {status:429,body:'{}'};}}),e=>e.code==='provider_rate_limit');assert.equal(count,2);
  count=0;await assert.rejects(callProvider({...args,transport:async()=>{count++;return {status:401,body:'secret upstream detail'};}}),e=>e.code==='provider_authentication'&&!e.message.includes('secret'));assert.equal(count,1);
});
test('refusals, truncation and invalid JSON are never treated as grading',async()=>{
  for(const body of ['not JSON',JSON.stringify({status:'incomplete',output:[]}),JSON.stringify({status:'completed',output:[{content:[{type:'refusal',refusal:'no'}]}]})]) {
    await assert.rejects(callProvider({provider:'openai',config:providerConfig,model:'fixture-model',system:'s',input:{},schema:sessionSchema,transport:async()=>({status:200,body})}),e=>e.code==='invalid_provider_response');
  }
});
test('cancellation produces a clear timeout without invented output',async()=>{
  const controller=new AbortController();controller.abort();
  await assert.rejects(callProvider({provider:'openai',config:providerConfig,model:'fixture-model',system:'s',input:{},schema:sessionSchema,signal:controller.signal,transport:async()=>{throw new Error('aborted');}}),e=>e.code==='timeout');
});
test('malformed questions, duplicate IDs, unexpected fields and invalid grades fail validation',()=>{
  assert.throws(()=>validateSession({questions:[question,question]},2));
  assert.throws(()=>validateSession({questions:[{...question,answer:'nan'}]},1));
  assert.throws(()=>validateSession({questions:[{...question,kind:'multipleChoice',options:['1','2']}]},1));
  assert.throws(()=>validateSession({questions:[{...question,hints:[]}]},1));
  assert.throws(()=>validateGrade({correct:'yes',feedback:'hi',reviewTopic:''}));
  assert.throws(()=>validateGrade({correct:true,feedback:'hi',reviewTopic:'',execute:'shell'}));
});
test('only configured, explicit model allowlists are exposed',()=>{
  assert.deepEqual(providersFromEnv({}),{});
  const result=providersFromEnv({OPENAI_API_KEY:'fixture',OPENAI_MODELS:'model-a,../../secret,YOUR_MODEL'});
  assert.deepEqual(result.openai.models,['model-a']);
});
test('quota survives restart and fails closed for corrupt persisted state',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ascend-quota-'));
  try {
    const q=new Quota(dir,2,2);q.consume(1800000000000);q.consume(1800000000000);
    const reloaded=new Quota(dir,2,2);assert.throws(()=>reloaded.consume(1800000000000),GatewayError);
    fs.writeFileSync(path.join(dir,'quota.json'),'{}');assert.throws(()=>new Quota(dir));
  } finally {fs.rmSync(dir,{recursive:true,force:true});}
});
async function withServer(fn, options={}) {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ascend-http-')); let calls=0;
  const quota=new Quota(dir,30,100);
  const server=createGateway({token,providers:{openai:providerConfig},quota,transport:async(_url, _headers, wire)=>{calls++;options.inspect?.(wire);if(options.beforeResponse) await options.beforeResponse();return {status:200,body:JSON.stringify(wrapper('openai',options.result || {questions:[question]}))};}});
  server.listen(0,'127.0.0.1');await once(server,'listening');
  const base=`http://127.0.0.1:${server.address().port}`;
  const post=(body,auth=token,route='/v1/session')=>fetch(base+route,{method:'POST',headers:{'content-type':'application/json',authorization:`Bearer ${auth}`},body:JSON.stringify(body)});
  try {await fn({base,post,quota,calls:()=>calls});} finally {server.closeAllConnections();await new Promise(resolve=>server.close(resolve));fs.rmSync(dir,{recursive:true,force:true});}
}
const request={requestID:'fixture-request',provider:'openai',model:'fixture-model',config};
test('HTTP requires authentication, validates input and keeps provider secrets private',()=>withServer(async({base,post,calls})=>{
  assert.equal((await post(request,'wrong')).status,401);
  assert.equal((await post({...request,url:'http://169.254.169.254'})).status,400);
  assert.equal((await post({...request,model:'unapproved'})).status,503);
  const response=await fetch(base+'/v1/config',{headers:{authorization:`Bearer ${token}`}});const body=await response.json();
  assert.deepEqual(body.providers.openai,['fixture-model']);assert.equal(body.providerTested,false);assert.equal(JSON.stringify(body).includes('test-fixture'),false);assert.equal(calls(),0);
}));
test('HTTP caches identical retry IDs without a second provider call and rejects changed content',()=>withServer(async({post,calls,quota})=>{
  assert.equal((await post(request)).status,200);assert.equal((await post(request)).status,200);assert.equal(calls(),1);assert.equal(quota.state.used,1);
  assert.equal((await post({...request,config:{...config,count:2}})).status,409);
}));
test('HTTP refuses an in-flight duplicate without consuming quota or generating twice',async()=>{
  let release, entered;
  const responseGate = new Promise(resolve=>{release=resolve;});
  const started = new Promise(resolve=>{entered=resolve;});
  await withServer(async({post,calls,quota})=>{
    const first = post(request);
    await started;
    try {
      const duplicate = await post(request);
      assert.equal(duplicate.status,409);assert.equal((await duplicate.json()).error.code,'request_pending');
      assert.equal(calls(),1);assert.equal(quota.state.used,1);
    } finally { release(); }
    assert.equal((await first).status,200);
    assert.equal((await post(request)).status,200);assert.equal(calls(),1);
  },{beforeResponse:()=>{entered();return responseGate;}});
});
test('HTTP rejects oversized requests and malformed provider output',()=>withServer(async({post})=>{
  assert.equal((await post({...request,config:{...config,subtopic:'x'.repeat(70000)}})).status,413);
  const response=await post(request);assert.equal(response.status,502);const body=await response.json();assert.equal(body.error.code,'invalid_provider_response');
},{result:{questions:[{...question,answer:'broken'}]}}));

test('chat uses the selected provider, preserves conversation order and validates before charging quota', () => withServer(async ({post, calls}) => {
  const messages = [{role:'user', content:'I have twenty minutes.'}, {role:'assistant', content:'What is due?'}, {role:'user', content:'A quiz tomorrow.'}];
  const body = {requestID:'chat-1', provider:'openai', model:'fixture-model', messages};
  const chat = value => post(value, token, '/v1/chat');
  assert.equal((await post(body, 'wrong', '/v1/chat')).status, 401);
  for (const invalid of [[], messages.slice(0, 2), [{role:'system', content:'Different role'}], [{role:'user', content:' '}], [{role:'user', content:'x'.repeat(4001)}]]) {
    assert.equal((await chat({...body, messages:invalid})).status, 400);
  }
  assert.equal(calls(), 0);
  const response = await chat(body);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {reply:'Try a practice quiz.'});
  assert.equal((await chat(body)).status, 200);
  assert.equal(calls(), 1);
}, {result:{reply:'Try a practice quiz.'}, inspect: wire => {
  const upstream = JSON.parse(wire);
  assert.equal(upstream.model, 'fixture-model');
  assert.deepEqual(JSON.parse(upstream.input).messages.map(m => m.content), ['I have twenty minutes.', 'What is due?', 'A quiz tomorrow.']);
}}));
test('chat rejects a malformed provider reply', () => withServer(async ({post}) => {
  const response = await post({requestID:'chat-2', provider:'openai', model:'fixture-model', messages:[{role:'user',content:'Hi'}]}, token, '/v1/chat');
  assert.equal(response.status, 502);
}, {result:{reply:''}}));

const {planSchema,validatePlan} = await import('../planning.mjs');
const plan = {summary:'A balanced week',categories:[],goals:[],quests:[],workouts:[{id:'new:push',name:'Push day',weekdays:[2,4,6],exercises:[{id:'new:press',name:'Press',muscles:['chest','triceps'],sets:3,prescription:'8 reps'}]}],quitting:[],preferences:{theme:null,subjects:null,widgets:null,muscleTargets:null,mathDifficulty:null,mathSeconds:null}};
const appContext = {day:'2026-11-25',timeZone:'America/Toronto',categories:[],goals:[],quests:[],workouts:[],quitting:[],theme:'shadow',subjects:[],widgets:[],muscleTargets:[],mathDifficulty:'Medium',mathSeconds:120};
test('all four providers carry the same app planning contract',async()=>{
  for(const provider of ['openai','anthropic','gemini','compatible']) {
    const result = await callProvider({provider,config:providerConfig,model:'fixture-model',system:'plan',input:{context:appContext},schema:planSchema,transport:async()=>({status:200,body:JSON.stringify(wrapper(provider,plan))})});
    assert.deepEqual(validatePlan(result),plan);
  }
});
test('plan validates muscle groups, dates, identifiers and allowed operations',()=>{
  for(const mutate of [p=>p.workouts[0].exercises[0].muscles=[], p=>p.workouts[0].weekdays=[8],p=>p.workouts[0].exercises[0].sets=0,p=>p.preferences.mathSeconds=7,p=>p.preferences.widgets=['gym','gym'],p=>p.completeAllQuests=true,p=>p.summary='',p=>delete p.preferences]) {
    const invalid=structuredClone(plan);mutate(invalid);assert.throws(()=>validatePlan(invalid));
  }
});
test('plan endpoint validates context before quota and caches retries',()=>withServer(async({post,calls})=>{
  const body={requestID:'plan-1',provider:'openai',model:'fixture-model',messages:[{role:'user',content:'Plan my week'}],context:appContext};
  assert.equal((await post({...body,context:{...appContext,health:{steps:100}}},token,'/v1/plan')).status,400);
  assert.equal(calls(),0);
  const response=await post(body,token,'/v1/plan');assert.equal(response.status,200);assert.deepEqual(await response.json(),plan);
  assert.equal((await post(body,token,'/v1/plan')).status,200);assert.equal(calls(),1);
},{result:plan,inspect:wire=>assert.deepEqual(JSON.parse(JSON.parse(wire).input).context,appContext)}));
test('invalid AI plan is rejected by endpoint before reaching the app',()=>withServer(async({post})=>{
  const response=await post({requestID:'plan-invalid',provider:'openai',model:'fixture-model',messages:[{role:'user',content:'Plan'}],context:appContext},token,'/v1/plan');
  assert.equal(response.status,502);
},{result:{...plan,preferences:{...plan.preferences,theme:'unknown'}}}));
test('compatible models can use JSON or prompted JSON without schema support',()=>{
  for(const outputMode of ['json','text']) {
    const request=adapterRequest('compatible',{...providerConfig,outputMode},'vendor/model:free','plan',{},planSchema);
    assert.ok(request.body.messages[0].content.includes(JSON.stringify(planSchema)));
    if(outputMode==='json') assert.deepEqual(request.body.response_format,{type:'json_object'});
    else assert.equal(request.body.response_format,undefined);
  }
  const result=providersFromEnv({COMPATIBLE_API_KEY:'fixture',COMPATIBLE_MODELS:'vendor/model:free,../../secret',COMPATIBLE_BASE_URL:'https://api.example.com/v1',COMPATIBLE_ALLOWED_HOSTS:'api.example.com',COMPATIBLE_OUTPUT_MODE:'text'});
  assert.deepEqual(result.compatible.models,['vendor/model:free']);assert.equal(result.compatible.outputMode,'text');
});
