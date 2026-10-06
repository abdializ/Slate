#pragma once

// Runs only in the main frame's isolated WebKit content world. The page can
// change its own styles, but cannot send arbitrary colors to the native bridge.
inline constexpr char kPageThemeJs[] = R"JS((function() {
 if (window.__slateThemeObserver) return;
 window.__slateThemeObserver = true;
 var last = null;
 var timer = 0;
 var fallback = 0;
 var observing = false;
 var paused = false;
 var canvas = document.createElement('canvas');
 canvas.width = canvas.height = 1;
 var context = canvas.getContext('2d');
 function hex(n) { return ('0' + n.toString(16)).slice(-2); }
 function color(value) {
  if (!value || !context) return '';
  try {
   context.clearRect(0, 0, 1, 1);
   context.fillStyle = 'rgba(0, 0, 0, 0)';
   context.fillStyle = value;
   context.fillRect(0, 0, 1, 1);
   var pixel = context.getImageData(0, 0, 1, 1).data;
   if (pixel[3] < 217) return '';
   return '#' + hex(pixel[0]) + hex(pixel[1]) + hex(pixel[2]);
  } catch (e) { return ''; }
 }
 function background(element) {
  if (!element) return '';
  try { return color(getComputedStyle(element).backgroundColor); }
  catch (e) { return ''; }
 }
 function backdrop() {
  var x = Math.max(0, Math.floor(innerWidth * 0.5));
  var ys = [Math.min(160, Math.floor(innerHeight * 0.18)), 56, 28, 8];
  for (var i = 0; i < ys.length; i++) {
   var element = document.elementFromPoint(x, ys[i]);
   for (var hops = 0; element && hops < 20; hops++, element = element.parentElement) {
    var value = background(element);
    if (value) return value;
   }
  }
  return '';
 }
 function metadata() {
  var metas = document.querySelectorAll('meta[name="theme-color" i],meta[name="msapplication-navbutton-color" i]');
  for (var i = 0; i < metas.length; i++) {
   var media = metas[i].getAttribute('media');
   if (media && window.matchMedia && !window.matchMedia(media).matches) continue;
   var value = color(metas[i].getAttribute('content'));
   if (value) return value;
  }
  return '';
 }
 function current() {
  return backdrop() || background(document.body) ||
   background(document.documentElement) || metadata() ||
   (getComputedStyle(document.documentElement).colorScheme.indexOf('dark') >= 0 ? '#121212' : '#ffffff');
 }
 function report() {
  timer = 0;
  if (paused || document.hidden) return;
  try {
   var value = current();
   if (value === last) return;
   last = value;
   window.webkit.messageHandlers.slateTheme.postMessage(value);
  } catch (e) {}
 }
 function schedule() {
  if (!paused && !document.hidden && !timer) timer = setTimeout(report, 300);
 }
 var observer = new MutationObserver(schedule);
 function resume() {
  if (paused || document.hidden) return;
  if (!observing) {
   observer.observe(document.documentElement, {
    subtree: true, childList: true, attributes: true,
    attributeFilter: ['class', 'style', 'content', 'media']
   });
   observing = true;
  }
  schedule();
  if (!fallback) fallback = setTimeout(function tick() {
   fallback = 0;
   if (paused || document.hidden) return;
   schedule();
   fallback = setTimeout(tick, 3000);
  }, 3000);
 }
 function suspend() {
  observer.disconnect(); observing = false;
  if (timer) clearTimeout(timer);
  if (fallback) clearTimeout(fallback);
  timer = fallback = 0;
 }
 resume();
 window.addEventListener('resize', schedule);
 window.addEventListener('popstate', schedule);
 window.addEventListener('hashchange', schedule);
 document.addEventListener('visibilitychange', function() {
  if (document.hidden) suspend(); else resume();
 });
 window.addEventListener('pagehide', function() { paused = true; suspend(); });
 window.addEventListener('pageshow', function() { paused = false; resume(); });
})();)JS";
