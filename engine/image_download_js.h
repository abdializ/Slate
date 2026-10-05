#pragma once

// Runs in WebKit's isolated client world. Only an actual user right-click on
// an HTTP(S) image replaces WebKit's context menu; other elements keep theirs.
static constexpr const char* kImageDownloadJs = R"SLATEJS((() => {
  document.addEventListener('contextmenu', event => {
    if (!event.isTrusted) return;
    const image = event.composedPath().find(node => node instanceof HTMLImageElement);
    if (!image) return;
    const source = image.currentSrc || image.src;
    if (!source || source.length > 8192) return;
    let url;
    try { url = new URL(source, document.baseURI); } catch (_) { return; }
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return;
    event.preventDefault();
    event.stopImmediatePropagation();
    window.webkit.messageHandlers.slateImageDownload.postMessage(url.href);
  }, true);
})();)SLATEJS";
