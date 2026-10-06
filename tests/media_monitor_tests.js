const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const header = fs.readFileSync(path.join(__dirname, '../engine/media_monitor_js.h'), 'utf8');
const script = header.split('R"JS(')[1].split(')JS"')[0];

function fixture({ad = false, hidden = false} = {}) {
  const listeners = new Map();
  const messages = [];
  const frameMessages = [];
  let pipCalls = 0;
  let mutation;
  let pending;
  let scans = 0;
  const videos = [];
  const attributes=new Set();
  class Element {}
  class HTMLMediaElement extends Element {}
  const video = Object.assign(new HTMLMediaElement(), {
    hasAttribute: name => attributes.has(name),
    paused: false, ended: false, muted: false, volume: 1, duration: 100,
    videoWidth: 1280, videoHeight: 720, webkitPresentationMode: 'inline',
    getBoundingClientRect: () => { scans++; return {width: hidden ? 0 : 640, height: hidden ? 0 : 360}; },
    closest: () => ad ? {} : null,
    webkitSetPresentationMode: function (mode) {
      this.webkitPresentationMode = mode;
      pipCalls++;
    }
  });
  videos.push(video);
  const document = {
    documentElement: {},
    getElementsByTagName: name => name === "video" ? videos : [],
    pictureInPictureElement: null,
    querySelectorAll: selector => selector === 'video' ? [video] : [],
    querySelector: selector => selector === 'video' ? video : null,
    addEventListener: (name, fn) => {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push(fn);
    }
  };
  const window = {
    webkit: {messageHandlers: {
      slateMedia: {postMessage: value => messages.push(value)},
      slatePiP: {postMessage: value => frameMessages.push(value)}
    }},
    addEventListener: document.addEventListener
  };
  const context = {window, document, Element, HTMLMediaElement,
    getComputedStyle: () => ({display: 'block', visibility: 'visible', opacity: '1'}),
    MutationObserver: class { constructor(fn) { mutation=fn; } observe() {} },
    setTimeout: fn => { pending = fn; return 1; }, clearTimeout: () => { pending = null; },
    Math, Date};
  vm.runInNewContext(script, context);
  const fire = (name, event) => (listeners.get(name) || []).forEach(fn => fn(event));
  return {video, messages, frameMessages, fire, attributes, mutate:()=>mutation(), flush:()=>{ const fn=pending; pending=null; if(fn) fn(); },
    pending:()=>!!pending, scans:()=>scans, videos, pipCalls: () => pipCalls};
}

{
  const f = fixture();
  assert.equal(f.messages.at(-1).user_started, false);
  f.fire('message', {data: {type: 'slatePiPEnter'}});
  assert.equal(f.pipCalls(), 0, 'autoplay must not enter PiP');
  f.fire('pointerdown', {isTrusted: true, target: f.video});
  f.fire('play', {target: f.video});
  assert.equal(f.messages.at(-1).user_started, true);
  f.fire('message', {data: {type: 'slatePiPEnter'}});
  assert.equal(f.pipCalls(), 1, 'user-started visible video can enter PiP');
  f.fire('message', {data: {type: 'slatePiPEnter', manual: true}});
  assert.equal(f.pipCalls(), 1, 'repeated requests must not disturb active native PiP');
}
for (const variant of [{ad: true}, {hidden: true}]) {
  const f = fixture(variant);
  f.fire('pointerdown', {isTrusted: true, target: f.video});
  f.fire('play', {target: f.video});
  assert.equal(f.messages.at(-1).user_started, false);
  f.fire('message', {data: {type: 'slatePiPEnter'}});
  assert.equal(f.pipCalls(), 0);
}
{
  const f = fixture();
  f.fire('message', {data: {type: 'slatePiPEnter', manual: true}});
  assert.equal(f.pipCalls(), 1, 'explicit toolbar action can enter native PiP');
}
for (const variant of [{ad: true}, {hidden: true}]) {
  const f = fixture(variant);
  f.fire('message', {data: {type: 'slatePiPEnter', manual: true}});
  assert.equal(f.pipCalls(), 0, 'toolbar action must not float an ad or hidden video');
}
{
  const f=fixture();
  f.fire('pointerdown',{isTrusted:true,target:f.video});
  f.fire('play',{target:f.video});
  f.video.webkitPresentationMode='picture-in-picture';
  f.fire('webkitpresentationmodechanged',{target:f.video});
  assert.equal(f.frameMessages.at(-1).active,true);
  assert.equal(f.frameMessages.at(-1).frame_id,f.messages.at(-1).frame_id);
  f.attributes.add('data-slate-ad-break'); f.mutate(); f.flush();
  assert.equal(f.messages.at(-1).video,false,'in-stream ads cannot become PiP candidates');
  assert.equal(f.messages.at(-1).pip,true,'an ad candidate change does not falsely end native PiP');
  f.attributes.delete('data-slate-ad-break'); f.mutate(); f.flush();
  assert.equal(f.messages.at(-1).user_started,true,'the same show resumes its trusted session after the ad');
}
console.log('Media intent and PiP eligibility tests passed');

{
 const f=fixture();
 f.fire('pointerdown',{isTrusted:true,target:f.video}); f.fire('play',{target:f.video});
 const before=f.scans();
 for(let i=0;i<1000;i++) f.mutate();
 assert.equal(f.scans(),before,'a DOM mutation burst does not repeatedly force layout');
 assert.ok(f.pending()); f.flush();
 const scans=f.scans()-before;
 assert.ok(scans>0 && scans<=6,'one bounded media check services the complete burst');
 f.video.isConnected=false; f.videos.length=0; f.mutate(); f.flush();
 assert.equal(f.messages.at(-1).has_video,false,'player removal clears stale media state');
 assert.equal(f.messages.at(-1).video,false,'detached players cannot keep a tab in media state');
 for(let i=0;i<1000;i++) f.mutate();
 assert.equal(f.pending(),false,'media-free documents schedule no mutation checks');
 console.log(`1000 media DOM mutations: ${scans} layout reads; media-free mutations: 0 scheduled checks`);
}
{
 const f=fixture(); f.mutate(); assert.ok(f.pending());
 f.fire('pagehide',{}); assert.equal(f.pending(),false,'page cache entry cancels queued work');
 const removed=f.messages.length;
 f.fire('pageshow',{});
 assert.equal(f.messages.length,removed+1,'page cache restore republishes an unchanged frame after native removal');
 assert.equal(f.messages.at(-1).has_video,true);
 assert.equal(f.messages.at(-1).removed,undefined);
}
