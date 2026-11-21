// File purpose: Contains the isolated main-frame script that reads page colors for Slate chrome.

#pragma once

// Runs only in the main frame's isolated WebKit content world. The page can
// change its own styles, but cannot send arbitrary colors to the native bridge.
// Slate note: Prefers authoritative <meta name="theme-color">, then a genuine fixed/sticky top
// header bar, then document.body / documentElement background. Never samples arbitrary scrolled
// content (such as feed photos/cards), and never polls on a timer.
inline constexpr char kPageThemeJs[] = R"JS((function() {
 if (window.__slateThemeObserver) return;
 window.__slateThemeObserver = true;
 var last = null;
 var timer = 0;
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
 function fixedHeader() {
  if (!document.elementFromPoint || innerWidth < 100) return '';
  var el = document.elementFromPoint(Math.floor(innerWidth * 0.5), 4);
  for (var hops = 0; el && hops < 12; hops++, el = el.parentElement) {
   if (el === document.body || el === document.documentElement) break;
   var tag = el.tagName;
   if (tag === 'IMG' || tag === 'VIDEO' || tag === 'PICTURE' || tag === 'CANVAS' || tag === 'SVG') continue;
   var st;
   try { st = getComputedStyle(el); } catch (e) { continue; }
   if (st.position !== 'fixed' && st.position !== 'sticky') continue;
   if (!el.getBoundingClientRect) continue;
   var r = el.getBoundingClientRect();
   if (r.top > 6 || r.height < 28 || r.height > 110 || r.width < innerWidth * 0.75) continue;
   var value = color(st.backgroundColor);
   if (value) return value;
  }
  return '';
 }
 function current() {
  return metadata() || fixedHeader() || background(document.body) ||
   background(document.documentElement) ||
   (getComputedStyle(document.documentElement).colorScheme.indexOf('dark') >= 0 ? '#141416' : '#ffffff');
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
    attributes: true,
    attributeFilter: ['class', 'style', 'data-theme', 'data-color-scheme']
   });
   if (document.body && document.body !== document.documentElement) {
    observer.observe(document.body, {
     attributes: true,
     attributeFilter: ['class', 'style', 'data-theme', 'data-color-scheme']
    });
   }
   if (document.head) {
    observer.observe(document.head, {
     subtree: true, childList: true, attributes: true,
     attributeFilter: ['content', 'media']
    });
   }
   observing = true;
  }
  schedule();
 }
 function suspend() {
  observer.disconnect(); observing = false;
  if (timer) clearTimeout(timer);
  timer = 0;
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
