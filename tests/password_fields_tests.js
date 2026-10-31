const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const crypto=require('node:crypto').webcrypto;
const dir=process.argv[2];
const turn=()=>new Promise(resolve=>setImmediate(resolve));
async function passkeys(){
  const window=new EventTarget();const requests=[];let getCalls=0,createCalls=0;
  class CredentialsContainer {get(){getCalls++;return Promise.resolve('native-get');}create(){createCalls++;return Promise.resolve('native-create');}}
  class PublicKeyCredential{};PublicKeyCredential.getClientCapabilities=()=>Promise.resolve({'extension:unknown':true});
  const navigator={credentials:new CredentialsContainer()};
  const globals={window,navigator,CredentialsContainer,PublicKeyCredential,
    AuthenticatorAssertionResponse:class{},AuthenticatorAttestationResponse:class{},
    crypto,TextEncoder,TextDecoder,ArrayBuffer,Uint8Array,Uint32Array,Event,CustomEvent,DOMException,btoa,atob};
  window.PublicKeyCredential=PublicKeyCredential;window.CredentialsContainer=CredentialsContainer;window.crypto=crypto;
  vm.runInNewContext(fs.readFileSync(dir+'/password-page-test.js','utf8'),globals);
  window.addEventListener('slate-passkeys-ask',event=>requests.push(JSON.parse(event.detail)));
  const reply=(request,value)=>window.dispatchEvent(new CustomEvent('slate-passkeys-answer',{detail:JSON.stringify({token:request.token,reply:value})}));
  assert.equal(await navigator.credentials.get({password:true}),'native-get');
  assert.equal(await navigator.credentials.create({password:true}),'native-create');
  assert.equal(getCalls,1);assert.equal(createCalls,1);
  const publicKey={challenge:new Uint8Array([0,1,2]),rpId:'example.com'};
  const result=navigator.credentials.get({publicKey});await turn();
  const request=requests.at(-1);assert.equal(request.kind,'get');assert.equal(request.challenge,'AAEC');
  assert.match(request.token,/^\d+-\d+-\d+-\d+$/);
  assert.equal(request.origin,undefined,'Page cannot choose the native caller origin');
  reply(request,{kind:'get',id:'AQI',clientDataJSON:'e30',authenticatorData:'Aw',signature:'BA',userHandle:'BQ',attachment:'platform'});
  const credential=await result;
  assert.ok(credential instanceof PublicKeyCredential);
  assert.deepEqual([...new Uint8Array(credential.rawId)],[1,2]);
  assert.equal(credential.toJSON().response.signature,'BA');
  assert.deepEqual([...new Uint8Array(credential.response.userHandle)],[5]);
  credential.toJSON=()=>({libraryOverride:true});assert.equal(credential.toJSON().libraryOverride,true);
  const aborted=new AbortController();aborted.abort();
  const before=requests.length;
  await assert.rejects(navigator.credentials.get({publicKey,signal:aborted.signal}),e=>e.name==='AbortError');
  assert.equal(requests.length,before,'Already-aborted request does not reach native code');
  const during=new AbortController();const pending=navigator.credentials.get({publicKey,signal:during.signal});
  await turn();const asked=requests.at(-1);during.abort();
  await assert.rejects(pending,e=>e.name==='AbortError');
  assert.equal(requests.at(-1).kind,'cancel');assert.equal(requests.at(-1).token,asked.token);
  reply(asked,{error:'NotAllowedError',message:'cancelled'});
  await assert.rejects(navigator.credentials.get({publicKey:{challenge:'invalid'}}),e=>e.name==='TypeError');
  const controller=new AbortController();
  const conditional=navigator.credentials.get({publicKey,mediation:'conditional',signal:controller.signal});
  await turn();const conditionalRequest=requests.at(-1);assert.equal(conditionalRequest.conditional,true);
  reply(conditionalRequest,{error:'Wait'});controller.abort();
  await assert.rejects(conditional,e=>e.name==='AbortError');
  const registering=navigator.credentials.create({publicKey:{challenge:new Uint8Array([8]),rp:{id:'example.com'},user:{id:new Uint8Array([1]),name:'test'},pubKeyCredParams:[{alg:-7}],extensions:{credProps:true}}});
  await turn();const registration=requests.at(-1);assert.equal(registration.kind,'create');
  reply(registration,{kind:'create',id:'AQI',clientDataJSON:'e30',attestationObject:'Aw',authenticatorData:'BA',publicKey:'BQ',publicKeyAlgorithm:-7,transports:['internal'],attachment:'platform'});
  const registered=await registering;
  assert.equal(registered.response.getPublicKeyAlgorithm(),-7);
  assert.equal(registered.getClientExtensionResults().credProps.rk,true);
}
function fields(){
  const handlers={},messages=[];
  class Input extends EventTarget {
    constructor(type,autocomplete=''){super();this.type=type;this.autocomplete=autocomplete;this.isConnected=true;this._value='';this.form=null;}
    get value(){return this._value;}set value(value){this._value=value;}
    getBoundingClientRect(){return {x:5,y:10,width:180,height:30};}
  }
  const user=new Input('text','username'),pass=new Input('password','current-password');
  const root={querySelectorAll:selector=>selector==='input[type=password]'?[pass]:[user,pass],querySelector:()=>pass.autocomplete==='new-password'?pass:null};
  user.form=pass.form=root;
  const document={activeElement:user,addEventListener:(name,fn)=>handlers[name]=fn};
  const window={addEventListener:(name,fn)=>handlers[name]=fn};
  const globals={window,document,HTMLInputElement:Input,crypto,Uint32Array,Event,setTimeout,
    webkit:{messageHandlers:{slatePasswords:{postMessage:body=>messages.push(body)}}}};
  vm.runInNewContext(fs.readFileSync(dir+'/password-field-test.js','utf8'),globals);
  handlers.focusin({target:user});const request=messages.at(-1);
  assert.equal(request.kind,'field');assert.equal(request.passwords,true);
  assert.equal(window.__slatePasswordFill('wrong','account','secret'),false);
  assert.equal(pass.value,'');
  assert.equal(window.__slatePasswordFill(request.token,'account','secret'),true);
  assert.equal(user.value,'account');assert.equal(pass.value,'secret');
  assert.ok(!JSON.stringify(messages).includes('secret'),'Focus messages never include password values');
  pass.isConnected=false;document.activeElement=new Input('text');
  assert.equal(window.__slatePasswordFill(request.token,'other','other-secret'),false,'Focus change invalidates fill');
  handlers.keydown({key:'Escape'});assert.equal(messages.at(-1).kind,'blur');
  document.activeElement=user;pass.isConnected=true;pass.autocomplete='new-password';
  const count=messages.length;handlers.focusin({target:user});
  assert.equal(messages.length,count,'Password creation fields do not receive saved passwords');
  pass.autocomplete='one-time-code';document.activeElement=pass;handlers.focusin({target:pass});
  assert.equal(messages.length,count,'One-time codes do not receive saved passwords');
  handlers.pagehide();assert.equal(window.__slatePasswordFill(request.token,'again','secret'),false,'Page exit invalidates fill');
}
(async()=>{await passkeys();fields();console.log('Field tokens, framework-aware filling, WebAuthn serialization, cancellation, and credential compatibility passed.');})().catch(error=>{console.error(error);process.exitCode=1;});
