const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../engine/webkit_shields.mm'), 'utf8');
const match = source.match(/kStreamAdDefuserSource = @R"JS\((\s*\(function\(\) \{[\s\S]*?)\)JS";/);
assert.ok(match, 'streaming handler source is present');
new vm.Script(match[1]);

function runScenario(hostname, adSelector) {
  let mutation; let flush; let observerOptions;
  let adActive = true;
  let tick;
  let adClicks = 0;
  let introClicks = 0;
  const visible = {
    textContent: 'Skip ad',
    className: '',
    disabled: false,
    getAttribute: () => null,
    getBoundingClientRect: () => ({ width: 40, height: 20 }),
    matches: () => true,
    click: () => { adClicks++; }
  };
  const intro = {
    ...visible,
    textContent: 'Skip intro',
    matches: () => false,
    click: () => { introClicks++; }
  };
  const attributes = new Set();
  const video = { paused: false, ended: false, muted: false, playbackRate: 1,
    hasAttribute: name => attributes.has(name),
    setAttribute: name => attributes.add(name), removeAttribute: name => attributes.delete(name) };
  const hidden = {...visible, getBoundingClientRect: () => ({width:0,height:0})};
  const document = {
    contentType: 'text/html', readyState: 'complete', body: {},
    querySelector: (selector) => adActive && selector.includes(adSelector) ? visible : null,
    querySelectorAll: selector => selector.includes(adSelector) ? (adActive ? [hidden,visible] : []) : (/skip/i.test(selector) ? [visible,intro] : []),
    getElementsByTagName: () => [video],
    addEventListener: () => {}
  };
  const window = {
    location: { hostname, pathname: '/watch' },
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1', pointerEvents: 'auto' })
  };
  const context = { window, document, MutationObserver: class { constructor(fn) { mutation=fn; } observe(root,options) { observerOptions=options; } },
    setInterval: (fn) => { tick = fn; }, setTimeout: fn => { flush=fn; return 1; },
    Request: class {}, Response: undefined, XMLHttpRequest: undefined,
    Date, Object, Array, JSON, WeakSet };
  vm.runInNewContext(match[1], context);
  assert.equal(adClicks, 1, `${hostname}: ad skip clicked`);
  assert.equal(introClicks, 0, `${hostname}: intro left alone`);
  assert.equal(video.muted, true, `${hostname}: ad muted`);
  assert.equal(video.playbackRate, hostname === 'www.twitch.tv' ? 1 : 16,
    `${hostname}: only finite ads accelerated`);
  assert.ok(attributes.has('data-slate-ad-break'), 'ad state is shared with the isolated media monitor');
  assert.ok(observerOptions.attributes, 'ad indicator attribute changes are observed');
  adActive = false;
  mutation(); flush();
  assert.ok(!attributes.has('data-slate-ad-break'), 'ad marker is cleared as soon as indicators disappear');
  assert.equal(video.muted, false, `${hostname}: sound restored after ad`);
  assert.equal(video.playbackRate, 1, `${hostname}: speed restored after ad`);
}

runScenario('play.hbomax.com', '[data-testid*="ad-countdown"]');
runScenario('play.max.com', '[data-testid*="ad-break"]');
runScenario('www.youtube.com', '#movie_player.ad-showing');
runScenario('www.twitch.tv', '[data-a-target="video-ad-label"]');
console.log('Streaming ad skip and playback restoration passed.');
