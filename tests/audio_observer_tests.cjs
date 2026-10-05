// Run with node tests/audio_observer_tests.cjs. No browser or network required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const header = fs.readFileSync(path.join(__dirname, '../engine/audio_compat_js.h'), 'utf8');
const script = header.split('R"JS(')[1].split(')JS"')[0];
let observer, fullScans = 0;
const document = {
  readyState: 'complete', baseURI: 'https://example.test/', documentElement: {},
  querySelectorAll() { fullScans++; return []; }
};
function audio(src) {
  const attrs = {src};
  return {nodeType: 1, tagName: 'AUDIO', dataset: {}, loads: 0,
    getAttribute(key) { return attrs[key] || ''; },
    removeAttribute(key) { delete attrs[key]; },
    querySelectorAll() { return []; },
    set src(value) { attrs.src = value; },
    load() { this.loads++; }
  };
}
vm.runInNewContext(script, {document, window: {}, URL,
  HTMLMediaElement: function Media() {},
  MutationObserver: class { constructor(callback) { observer = callback; } observe() {} }
});
assert.equal(fullScans, 1);
const unrelated = {nodeType:1, tagName:'DIV', querySelectorAll() { return []; }};
for (let i=0; i<100; i++) observer([{target:unrelated, addedNodes:[unrelated]}]);
assert.equal(fullScans, 1, 'Unrelated mutations must not scan the whole document');
const inserted = audio('clip.m4a');
observer([{target:unrelated, addedNodes:[inserted]}]);
assert.equal(inserted.loads, 1);
assert.match(inserted.getAttribute('src'), /^slate-audio:/);
observer([{target:unrelated, addedNodes:[inserted]}]);
assert.equal(inserted.loads, 1, 'An already bridged audio element must not reload');
const nested = audio('nested.aac');
observer([{target:unrelated, addedNodes:[{nodeType:1, querySelectorAll() { return [nested]; }}]}]);
assert.equal(nested.loads, 1);
const sourceParent = audio('');
sourceParent.querySelectorAll = () => [{getAttribute(key) { return key==='src' ? 'source.m4a' : ''; }, remove() {}}];
observer([{target:sourceParent, addedNodes:[]}]);
assert.equal(sourceParent.loads, 1, 'Source changes must still prepare the parent audio');
console.log('audio observer regression checks passed');
