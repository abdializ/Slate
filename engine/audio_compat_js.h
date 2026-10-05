#pragma once
// Rewrites AAC/M4A <audio> onto a WAV custom-scheme URL. Chromium will not
// request <source type="audio/mp4">, and a .m4a URL is treated as AAC. The
// browser process transcodes with AudioToolbox and returns WAV bytes.
inline constexpr char kAudioCompatJs[] = R"JS((function(){
 if(window.__slateAudioCompat) return;
 window.__slateAudioCompat=1;
 function looksAac(url,type){
  var path=((url||'').split('?')[0]||'').toLowerCase();
  var kind=(type||'').toLowerCase();
  if(path.indexOf('slate-audio:')===0) return false;
  return /\.(m4a|aac)$/.test(path) || kind==='audio/mp4' || kind==='audio/aac' ||
   kind==='audio/x-m4a' || kind==='audio/m4a';
 }
 function absUrl(url){
  try { return new URL(url, document.baseURI).href; } catch(e) { return ''; }
 }
 function bridge(url){
  return 'slate-audio://bridge/clip.wav?u='+encodeURIComponent(url);
 }
 function pickUrl(audio){
  if(!audio || audio.tagName!=='AUDIO') return '';
  var url=audio.getAttribute('src')||'';
  if(looksAac(url, audio.getAttribute('type')||'')) return absUrl(url);
  var sources=audio.querySelectorAll('source');
  for(var i=0;i<sources.length;i++){
   var src=sources[i].getAttribute('src')||'';
   if(looksAac(src, sources[i].getAttribute('type')||'')) return absUrl(src);
  }
  if(audio.currentSrc && looksAac(audio.currentSrc,'')) return audio.currentSrc;
  return '';
 }
 function prepare(audio){
  var url=pickUrl(audio);
  if(!url || !/^https?:/i.test(url)) return false;
  var next=bridge(url);
  if(audio.dataset.slateAudio===url && (audio.getAttribute('src')||'').indexOf('slate-audio:')===0)
   return true;
  audio.dataset.slateAudio=url;
  var leftover=audio.querySelectorAll('source');
  for(var i=0;i<leftover.length;i++) leftover[i].remove();
  audio.removeAttribute('type');
  audio.src=next;
  try { audio.load(); } catch(e) {}
  return true;
 }
 var origPlay=HTMLMediaElement.prototype.play;
 HTMLMediaElement.prototype.play=function(){
  if(this.tagName==='AUDIO') prepare(this);
  return origPlay.apply(this, arguments);
 };
 function scan(root){
  root=root && root.querySelectorAll ? root : document;
  if(root.tagName==='AUDIO') prepare(root);
  var nodes=root.querySelectorAll('audio');
  for(var i=0;i<nodes.length;i++) prepare(nodes[i]);
 }
 function watch(){
  scan();
  if(!document.documentElement || window.__slateAudioObserver) return;
  window.__slateAudioObserver=1;
  // Inspect changed subtrees, not the entire page for every DOM mutation.
  new MutationObserver(function(records){
   records.forEach(function(record){
    if(record.target.tagName==='AUDIO') prepare(record.target);
    record.addedNodes.forEach(function(node){
     if(node.nodeType===1) scan(node);
    });
   });
  }).observe(document.documentElement,{subtree:true,childList:true});
 }
 if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', watch);
 else watch();
})();)JS";
