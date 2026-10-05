#pragma once
// Audible-tab reporting and automatic picture-in-picture when the page is
// left. Does not change codecs, sandbox, or autoplay policy.
inline constexpr char kPageChromeJs[] = R"JS((function(){
 if(window.__slatePageChrome) return;
 window.__slatePageChrome=1;
 function videos(){
  var list=[];
  try { list=Array.prototype.slice.call(document.querySelectorAll('video, .html5-main-video, .video-stream')); }
  catch(e) {}
  return list;
 }
 function pickVideo(){
  var list=videos();
  var best=null, score=-1;
  for(var i=0;i<list.length;i++){
   var v=list[i];
   if(!v || v.ended) continue;
   try { v.disablePictureInPicture=false; } catch(e) {}
   if(v.paused && v.currentTime<0.05) continue;
   var s=(v.paused?0:10)+(v.readyState||0)+((v.videoWidth||0)*(v.videoHeight||0))/100000;
   if(s>score){ score=s; best=v; }
  }
  if(best) return best;
  for(var j=0;j<list.length;j++) if(list[j] && !list[j].paused) return list[j];
  return list[0]||null;
 }
 function audibleNow(){
  var nodes=document.querySelectorAll('audio,video');
  for(var i=0;i<nodes.length;i++){
   var n=nodes[i];
   if(!n.paused && !n.muted && n.volume>0) return true;
  }
  return false;
 }
 var lastA=-1,lastV=-1;
 function report(){
  var a=audibleNow()?1:0;
  var video=pickVideo();
  var v=video && !video.paused ? 1 : 0;
  if(a===lastA && v===lastV) return;
  lastA=a; lastV=v;
  try { console.log('SLATE_MEDIAUI audible='+a+' video='+v); } catch(e) {}
 }
 function setSession(v){
  try {
   if(!navigator.mediaSession) return;
   navigator.mediaSession.playbackState=(!v || v.paused)?'paused':'playing';
   if(!navigator.mediaSession.metadata)
    navigator.mediaSession.metadata=new MediaMetadata({title:document.title||'Slate',artist:location.hostname||''});
  } catch(e) {}
 }
 window.__slateEnterPip=function(){
  var v=pickVideo();
  try { console.log('SLATE_PIP enter enabled='+(!!document.pictureInPictureEnabled)+' video='+(v?1:0)+' paused='+(v&&v.paused?1:0)); } catch(e) {}
  if(!v) return false;
  if(document.pictureInPictureElement===v) return true;
  v.disablePictureInPicture=false;
  setSession(v);
  try {
   var p=v.requestPictureInPicture();
   if(p && p.then) p.then(function(){ console.log('SLATE_PIP ok'); }).catch(function(err){ console.log('SLATE_PIP fail '+(err&&err.name)+' '+(err&&err.message)); });
   return true;
  } catch(e) { console.log('SLATE_PIP throw '+e); return false; }
 };
 window.__slateExitPip=function(){
  if(!document.pictureInPictureElement) return;
  try {
   var p=document.exitPictureInPicture();
   if(p && p.catch) p.catch(function(){});
  } catch(e) {}
 };
 function hook(node){
  if(!node || node.__slateUiHook) return;
  node.__slateUiHook=1;
  node.disablePictureInPicture=false;
  ['play','pause','volumechange','ended','emptied'].forEach(function(ev){
   node.addEventListener(ev, function(){ setSession(node); report(); }, true);
  });
 }
 function scan(){
  videos().forEach(hook);
  document.querySelectorAll('audio').forEach(hook);
  report();
 }
 try {
  if(navigator.mediaSession){
   navigator.mediaSession.setActionHandler('enterpictureinpicture', function(){ window.__slateEnterPip(); });
   navigator.mediaSession.setActionHandler('play', function(){});
  }
 } catch(e) {}
 document.addEventListener('visibilitychange', function(){
  if(document.visibilityState==='hidden') window.__slateEnterPip();
 }, true);
 try {
  var obs=new MutationObserver(function(){
   if(window.__slateScanTO) return;
   window.__slateScanTO=setTimeout(function(){ window.__slateScanTO=0; scan(); }, 400);
  });
  if(document.documentElement) obs.observe(document.documentElement,{childList:true,subtree:true});
 } catch(e) {}
 scan();
 setInterval(scan, 4000);
 if(window===window.top){
  function hexFrom(css){
   if(!css) return '';
   try {
    var d=document.createElement('div');
    d.style.color=css;
    (document.documentElement||document.body).appendChild(d);
    var computed=getComputedStyle(d).color;
    d.remove();
    var m=computed.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([0-9.]+))?\)/);
    if(!m) return '';
    if(m[4]!==undefined && parseFloat(m[4])<0.12) return '';
    function h(n){ n=Math.max(0,Math.min(255,parseInt(n,10))); return ('0'+n.toString(16)).slice(-2); }
    return '#'+h(m[1])+h(m[2])+h(m[3]);
   } catch(e) { return ''; }
  }
  function opaqueHex(el){
   if(!el) return '';
   try { return hexFrom(getComputedStyle(el).backgroundColor); }
   catch(e) { return ''; }
  }
  function themeFromMeta(){
   var metas=document.querySelectorAll('meta[name="theme-color" i], meta[name="msapplication-navbutton-color" i]');
   for(var i=0;i<metas.length;i++){
    var media=metas[i].getAttribute('media');
    if(media && window.matchMedia && !window.matchMedia(media).matches) continue;
    var color=hexFrom(metas[i].getAttribute('content'));
    if(color) return color;
   }
   return '';
  }
  function sampleBackdrop(){
   try {
    var x=Math.max(24, Math.min(window.innerWidth-24, Math.floor(window.innerWidth*0.5)));
    var ys=[8, 28, 56, Math.min(120, Math.floor(window.innerHeight*0.18))];
    for(var i=0;i<ys.length;i++){
     var el=document.elementFromPoint(x, ys[i]);
     var hops=0;
     while(el && hops++<14){
      var c=opaqueHex(el);
      if(c) return c;
      el=el.parentElement;
     }
    }
   } catch(e) {}
   return '';
  }
  function pageTheme(){
   var sampled=sampleBackdrop();
   if(sampled) return sampled;
   var body=opaqueHex(document.body);
   if(body) return body;
   var html=opaqueHex(document.documentElement);
   if(html) return html;
   var nodes=document.querySelectorAll('main,#root,#__next,#app,.app,ytd-app,[data-theme],[role="main"]');
   for(var i=0;i<nodes.length && i<10;i++){
    var c=opaqueHex(nodes[i]);
    if(c) return c;
   }
   return themeFromMeta();
  }
  function reportTheme(){
   if(window.__slateThemeTO) return;
   window.__slateThemeTO=setTimeout(function(){
    window.__slateThemeTO=0;
    var c=pageTheme();
    if(c===window.__slateThemeLast) return;
    window.__slateThemeLast=c;
    try { console.log('SLATE_THEME '+(c||'none')); } catch(e) {}
   }, 280);
  }
  reportTheme();
  setTimeout(reportTheme, 300);
  setTimeout(reportTheme, 1200);
  try {
   if(document.head) new MutationObserver(reportTheme).observe(document.head,{childList:true,subtree:true,attributes:true,attributeFilter:['content','media','name','style']});
   if(document.documentElement) new MutationObserver(reportTheme).observe(document.documentElement,{attributes:true,attributeFilter:['style','class']});
   if(document.body) new MutationObserver(reportTheme).observe(document.body,{attributes:true,attributeFilter:['style','class']});
  } catch(e) {}
  try {
   if(window.matchMedia) window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', reportTheme);
  } catch(e) {}
 }
})();
)JS";
