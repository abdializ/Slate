#pragma once
// Page-level media diagnostics plus a VP9/AV1 mediaCapabilities correction.
// Chromium reports those types as supported=false even when canPlayType and
// local playback succeed; sites then skip them and try H.264. Do not advertise
// H.264/AAC, replace MSE, or spoof canPlayType.
inline constexpr char kMediaCompatJs[] = R"JS((function(){
 if(window.__slateMediaCompat) return;
 window.__slateMediaCompat=1;
 function log(name, value){
  try { console.log('SLATE_MEDIA '+name+'='+value); } catch(e) {}
 }
 if(navigator.mediaCapabilities && navigator.mediaCapabilities.decodingInfo){
  var origMc=navigator.mediaCapabilities.decodingInfo.bind(navigator.mediaCapabilities);
  navigator.mediaCapabilities.decodingInfo=function(config){
   return origMc(config).then(function(info){
    try {
     var video=(config && config.video && config.video.contentType) || '';
     var audio=(config && config.audio && config.audio.contentType) || '';
     var blob=video+' '+audio;
     if(/avc[13]|mp4a|hvc1|hev1|ac-3|ec-3/i.test(blob)) return info;
     if(info.supported) return info;
     if(!/vp9|vp09|av01|opus/i.test(blob)) return info;
     var probe=document.createElement('video');
     if(video && !probe.canPlayType(video)) return info;
     if(audio && !probe.canPlayType(audio)) return info;
     log('mc.correct', video+' audio='+audio+' was supported=false');
     return {supported:true, smooth:true, powerEfficient:!!info.powerEfficient};
    } catch(e) { return info; }
   });
  };
 }
 function dump(){
  var v=document.createElement('video');
  var types=[
   ['h264','video/mp4; codecs="avc1.42E01E"'],
   ['aac','audio/mp4; codecs="mp4a.40.2"'],
   ['vp9.webm','video/webm; codecs="vp9"'],
   ['vp9.mp4','video/mp4; codecs="vp09.00.10.08"'],
   ['av1.mp4','video/mp4; codecs="av01.0.05M.08"'],
   ['opus','audio/webm; codecs="opus"'],
   ['hls','application/vnd.apple.mpegurl']
  ];
  log('ua', navigator.userAgent);
  log('mse', !!window.MediaSource);
  log('eme', typeof navigator.requestMediaKeySystemAccess==='function');
  log('webcodecs', typeof window.VideoDecoder==='function');
  log('webrtc', !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia));
  types.forEach(function(pair){
   log('canPlay.'+pair[0], v.canPlayType(pair[1])||'no');
   if(window.MediaSource) log('mse.'+pair[0], MediaSource.isTypeSupported(pair[1]));
  });
  if(window.VideoDecoder && VideoDecoder.isConfigSupported){
   ['avc1.42E01E','vp09.00.10.08','av01.0.05M.08'].forEach(function(codec){
    VideoDecoder.isConfigSupported({codec:codec}).then(function(info){
     log('webcodecs.'+codec, !!info.supported);
    }).catch(function(err){ log('webcodecs.'+codec, err.name+':'+err.message); });
   });
  }
 }
 if(window===window.top) dump();
 if(window.MediaSource && MediaSource.prototype && MediaSource.prototype.addSourceBuffer){
  var origAdd=MediaSource.prototype.addSourceBuffer;
  MediaSource.prototype.addSourceBuffer=function(type){
   log('addSourceBuffer', type);
   try { return origAdd.call(this, type); }
   catch(err){
    log('addSourceBuffer.error', err.name+':'+err.message+' type='+type);
    throw err;
   }
  };
 }
 function bufferedEnd(node){
  try {
   if(!node.buffered || !node.buffered.length) return 0;
   return node.buffered.end(node.buffered.length-1);
  } catch(e) { return 0; }
 }
 function attach(node){
  if(!node || node.__slateMediaHooked) return;
  if(node.tagName!=='VIDEO' && node.tagName!=='AUDIO') return;
  node.__slateMediaHooked=1;
  node.addEventListener('playing', function(){
   log(node.tagName.toLowerCase()+'.playing', (node.currentSrc||'').slice(0,180)+' t='+node.currentTime);
  });
  node.addEventListener('timeupdate', function(){
   if(node.__slateMediaTime || node.currentTime<0.4) return;
   node.__slateMediaTime=1;
   log(node.tagName.toLowerCase()+'.time', node.currentTime.toFixed(2)+' src='+(node.currentSrc||'').slice(0,120));
  });
  node.addEventListener('error', function(){
   var err=node.error;
   log(node.tagName.toLowerCase()+'.error', (err?(err.code+':'+(err.message||'')):'unknown')+' src='+(node.currentSrc||''));
  });
 }
 function scan(){
  if(window.__slateMediaScanTO) return;
  window.__slateMediaScanTO=setTimeout(function(){
   window.__slateMediaScanTO=0;
   var nodes=document.querySelectorAll('video,audio');
   for(var i=0;i<nodes.length;i++) attach(nodes[i]);
  }, 400);
 }
 document.addEventListener('error', function(event){
  attach(event.target);
 }, true);
 if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', scan);
 else scan();
 if(document.documentElement && !window.__slateMediaObserver){
  window.__slateMediaObserver=1;
  new MutationObserver(scan).observe(document.documentElement,{subtree:true,childList:true});
 }
})();)JS";

inline constexpr char kMediaPlayMutedJs[] = R"JS((function(){
 function log(name, value){
  try { console.log('SLATE_MEDIA '+name+'='+value); } catch(e) {}
 }
 var nodes=document.querySelectorAll('video,audio');
 log('playmuted.count', nodes.length);
 for(var i=0;i<nodes.length;i++){
  (function(node){
   try { node.muted=true; node.volume=0; } catch(e) {}
   var play=node.play();
   if(play && play.then){
    play.then(function(){
     log('playmuted.ok', node.tagName.toLowerCase()+' t='+node.currentTime+' rs='+node.readyState);
    }).catch(function(err){
     log('playmuted.err', err.name+':'+err.message);
    });
   }
  })(nodes[i]);
 }
})();)JS";
