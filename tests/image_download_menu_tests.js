const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(`${__dirname}/../engine/image_download_js.h`, 'utf8');
const script = source.match(/R"SLATEJS\(([\s\S]*?)\)SLATEJS"/)[1];
let handler;
const messages = [];
class HTMLImageElement {}
const context = {
  HTMLImageElement,
  URL,
  document: {
    baseURI: 'https://images.example/results',
    addEventListener(type, callback, capture) {
      assert.equal(type, 'contextmenu');
      assert.equal(capture, true);
      handler = callback;
    },
  },
  window: {webkit: {messageHandlers: {slateImageDownload: {postMessage(url) {
    messages.push(url);
  }}}}},
};
vm.runInNewContext(script, context);

function rightClick(path, trusted = true) {
  let prevented = false;
  let stopped = false;
  handler({
    isTrusted: trusted,
    composedPath: () => path,
    preventDefault: () => { prevented = true; },
    stopImmediatePropagation: () => { stopped = true; },
  });
  return {prevented, stopped};
}

const image = new HTMLImageElement();
image.currentSrc = 'https://encrypted-tbn0.gstatic.com/images?q=tbn:sample';
assert.deepEqual(rightClick([image]), {prevented: true, stopped: true});
assert.equal(messages.pop(), image.currentSrc);
assert.deepEqual(rightClick([{tagName: 'A'}]), {prevented: false, stopped: false});
assert.deepEqual(rightClick([image], false), {prevented: false, stopped: false});
image.currentSrc = 'file:///etc/passwd';
assert.deepEqual(rightClick([image]), {prevented: false, stopped: false});
assert.equal(messages.length, 0);
console.log('Image right-click menu behavior passed.');
