// Disney playback responses must retain their original timeline and API semantics.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../engine/webkit_shields.mm'), 'utf8');
const script = source.match(/kStreamAdDefuserSource = @R"JS\((\s*\(function\(\) \{[\s\S]*?)\)JS";/)[1];

async function check(hostname) {
  const payload = {
    ads: { metadata: {url: 'ad-metadata'}, document: 'ad-document', dxc: {}, live: {}, vod: {},
      unknownPlayerField: {keep: true} },
    stream: { insertion: { timeline: 'session-timeline', offset: 10 }, sources: [
      { type: 'video', url: 'https://media.example/video.m3u8', insertion: { keyId: 'video-key', discontinuity: 2 } },
      { type: 'audio', url: 'https://media.example/audio.m3u8', insertion: { keyId: 'audio-key', discontinuity: 2 } }
    ] },
    pods: [{ start: 10, end: 20, ads: [{duration: 10}] }], breaks: [{ start: 10 }],
    drm: { licenseUrl: 'https://license.example/session' }
  };
  const text = JSON.stringify(payload);
  const expected = JSON.parse(text);
  expected.ads = {unknownPlayerField: {keep: true}};
  const json = { parse: JSON.parse, stringify: JSON.stringify };
  class Response {
    constructor(value) { this.value = value; this.ok = true; this.bodyUsed = false; }
    json() { this.bodyUsed = true; return Promise.resolve().then(() => JSON.parse(this.value)); }
    clone() { throw new Error('The helper must not clone or consume fetch responses'); }
    static json(value) { return new Response(JSON.stringify(value)); }
  }
  class XHR {
    constructor() { this.responseType = ''; }
    open(method, url) { this.url = url; }
    get response() { return this.responseType === 'json' ? JSON.parse(text) : text; }
    get responseText() { return text; }
  }
  const response = new Response(text);
  const fetch = () => Promise.resolve(response);
  const originals = { parse: json.parse, responseJSON: Response.prototype.json, xhrOpen: XHR.prototype.open,
    xhrResponse: Object.getOwnPropertyDescriptor(XHR.prototype, 'response').get,
    xhrText: Object.getOwnPropertyDescriptor(XHR.prototype, 'responseText').get };
  const attributes = new Set();
  let rateWrites = 0, muteWrites = 0;
  const video = { mediaKeys: {}, paused: false, ended: false,
    get playbackRate() { return 1; }, set playbackRate(_) { rateWrites++; },
    get muted() { return false; }, set muted(_) { muteWrites++; },
    hasAttribute: x => attributes.has(x), setAttribute: x => attributes.add(x), removeAttribute: x => attributes.delete(x) };
  const adBadge = { getBoundingClientRect: () => ({width: 50, height: 20}) };
  const document = { contentType: 'text/html', readyState: 'complete', body: {},
    querySelectorAll: selector => selector.includes('ad-timer') ? [adBadge] : [],
    getElementsByTagName: () => [video], addEventListener() {} };
  const window = { location: { hostname, pathname: '/play/session' }, fetch,
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1', pointerEvents: 'auto' }) };
  vm.runInNewContext(script, { window, document, JSON: json, Response, XMLHttpRequest: XHR, Request: class {},
    MutationObserver: class { observe() {} }, setInterval() {}, setTimeout() {}, Date, Object, Array, WeakSet });
  assert.equal(window.fetch, fetch, `${hostname}: fetch must remain the native function`);
  assert.equal(XHR.prototype.open, originals.xhrOpen, 'XHR is not intercepted');
  assert.equal(Object.getOwnPropertyDescriptor(XHR.prototype, 'responseText').get, originals.xhrText);
  const result = await window.fetch('https://disney.api.example/playbackInfo');
  assert.equal(result, response, 'The original response and streaming body are retained');
  assert.equal(result.bodyUsed, false, 'Fetch does not pre-consume the body');
  assert.deepEqual(await result.json(), expected);
  assert.equal(result.bodyUsed, true, 'The real json method consumes the real response');
  let reviverCalls = 0;
  assert.deepEqual(json.parse(text, (key,value) => { reviverCalls++; return value; }), expected,
    'Only known ad configuration is removed; playback fields and reviver survive');
  assert.ok(reviverCalls > 10);
  assert.throws(() => json.parse('{'), SyntaxError);
  assert.deepEqual(json.parse('[1,null,"text"]'), [1,null,'text']);
  assert.deepEqual(json.parse('{"ads":[{"id":"timeline-ad"}]}'), {ads:[{id:'timeline-ad'}]});
  assert.deepEqual(json.parse('{"vod":{"media":"keep"},"metadata":"keep"}'), {vod:{media:'keep'},metadata:'keep'});
  const frozen = Object.freeze({vod: 'keep-frozen'});
  assert.equal(json.parse('{}', () => ({ads:frozen})).ads, frozen, 'Frozen results do not throw');
  const failure = new Error('reviver failed');
  assert.throws(() => json.parse('{}', () => {throw failure;}), e => e === failure);
  await assert.rejects(new Response('{').json(), SyntaxError);
  const xhr = new XHR(); xhr.open('GET','https://bamgrid.com/playbackInfo');
  assert.equal(xhr.response,text); assert.equal(xhr.responseText,text);
  xhr.responseType='json'; assert.deepEqual(xhr.response,expected);
  assert.equal(rateWrites,0,'An ad badge must not change protected playback speed');
  assert.equal(muteWrites,0,'An ad badge must not change the shared protected video’s audio');
}
(async () => {
  await check('disneyplus.com');
  await check('www.disneyplus.com');
  await check('play.disneyplus.com');
  console.log('Disney ad configuration filtering, playback API semantics, and audio/video timeline preservation passed.');
})().catch(error => { console.error(error); process.exitCode=1; });
