#pragma once

namespace slate {

// Event-driven media state. A page calling play() is not evidence of user intent.
inline constexpr char kMediaMonitorJs[] = R"JS(
(function () {
  'use strict';
  if (window.__slateMediaMonitor) return;
  window.__slateMediaMonitor = true;
  const trusted = new WeakSet();
  let recentGesture = 0;
  let primary = null;
  let last = '';
  let lastPip = false;
  const frameId = Math.random().toString(36).slice(2) + Date.now().toString(36);

  function adCandidate(video) {
    if (video.isAdCandidate || (video.hasAttribute && (video.hasAttribute('data-ad') || video.hasAttribute('data-slate-ad') || video.hasAttribute('data-slate-ad-break')))) return true;
    return !!(video.closest && video.closest('[class*="ad-container"], [class*="video-ad"], [id*="player-ads"], [data-ad], [data-ad-slot], .ad-showing, .ytp-ad-player-overlay, [class*="ad-interrupting"], [class*="ad-box"], [class*="sponsored"], [id*="google_ads"]'));
  }
  function visible(video) {
    const box = video.getBoundingClientRect();
    const style = typeof getComputedStyle === 'function' ? getComputedStyle(video) : {};
    if (box.width < 160 || box.height < 90) return false;
    if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) <= 0.05) return false;
    if (typeof window !== 'undefined' && box.left !== undefined && box.right !== undefined) {
      const viewW = window.innerWidth || (document.documentElement && document.documentElement.clientWidth) || 10000;
      const viewH = window.innerHeight || (document.documentElement && document.documentElement.clientHeight) || 10000;
      if (box.right < 0 || box.bottom < 0 || box.left > viewW || box.top > viewH) return false;
    }
    return true;
  }
  function eligible(video) {
    return !!video && !video.paused && !video.ended && trusted.has(video) &&
      visible(video) && !adCandidate(video);
  }
  function candidateScore(video) {
    if (!eligible(video)) return -1;
    const box = video.getBoundingClientRect();
    let score = Math.min(box.width * box.height / 1000, 1000);
    if (!video.muted && video.volume > 0) score += 100;
    if (video.duration > 60 || !Number.isFinite(video.duration)) score += 50;
    if (trusted.has(video)) score += 200;
    if (video.closest && video.closest('.html5-video-player, #movie_player, [class*="player-instance"], [class*="main-player"], .video-js, .jwplayer')) score += 150;
    return score;
  }
  function choose() {
    let best = null, score = -1;
    for (const video of document.querySelectorAll('video')) {
      const next = candidateScore(video);
      if (next > score) { best = video; score = next; }
    }
    return best;
  }
  function report() {
    const best = choose();
    if (best) primary = best;
    const video = best || (eligible(primary) ? primary : null);
    let audioPlaying = false;
    for (const audio of document.querySelectorAll('audio')) {
      if (!audio.paused && !audio.ended && !audio.muted && audio.volume > 0 && trusted.has(audio)) {
        audioPlaying = true;
        break;
      }
    }
    let anyPip = !!document.pictureInPictureElement;
    if (!anyPip) {
      for (const v of document.querySelectorAll('video')) {
        if (v.webkitPresentationMode === 'picture-in-picture') {
          anyPip = true;
          break;
        }
      }
    }
    const data = {
      frame_id: frameId,
      audible: audioPlaying || (!!video && !video.muted && video.volume > 0),
      video: !!video,
      has_video: !!document.querySelector('video'),
      user_started: !!video,
      candidate_score: video ? candidateScore(video) : -1,
      width: video ? video.videoWidth : 0,
      height: video ? video.videoHeight : 0,
      pip: anyPip
    };
    const key = JSON.stringify(data);
    if (key === last) return;
    last = key;
    try { window.webkit.messageHandlers.slateMedia.postMessage(data); } catch (_) {}
    if (data.pip !== lastPip) {
      lastPip = data.pip;
      try { window.webkit.messageHandlers.slatePiP.postMessage({frame_id:frameId, active:data.pip}); } catch (_) {}
    }
  }
  function mediaNear(target) {
    if (!(target instanceof Element)) return null;
    if (target instanceof HTMLMediaElement) return target;
    const player = target.closest && target.closest('[class*="player"], [id*="player"], [class*="control"], [aria-label*="Play"], [title*="Play"], [aria-label*="Pause"], [title*="Pause"]');
    if (!player) return null;
    return (player.querySelector && player.querySelector('video, audio')) || (document.querySelector && document.querySelector('video, audio'));
  }
  function gesture(event) {
    if (!event.isTrusted) return;
    const media = mediaNear(event.target);
    if (media) { trusted.add(media); recentGesture = Date.now(); }
  }
  document.addEventListener('pointerdown', gesture, true);
  document.addEventListener('click', gesture, true);
  document.addEventListener('keydown', function (event) {
    if (!event.isTrusted || ![' ', 'Enter', 'k', 'K'].includes(event.key)) return;
    gesture(event);
  }, true);
  document.addEventListener('play', function (event) {
    if (event.target instanceof HTMLMediaElement && Date.now() - recentGesture < 3000)
      trusted.add(event.target);
    report();
  }, true);
  for (const name of ['pause', 'ended', 'volumechange', 'loadedmetadata',
                      'enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged'])
    document.addEventListener(name, report, true);
  window.addEventListener('pagehide', function () {
    try { window.webkit.messageHandlers.slateMedia.postMessage({frame_id:frameId, removed:true}); } catch (_) {}
  });
  window.addEventListener('message', function (event) {
    if (event.data && event.data.type === 'slatePiPExit') {
      for (const frame of document.querySelectorAll('iframe')) {
        try { frame.contentWindow.postMessage(event.data, '*'); } catch (_) {}
      }
      if (event.data.frameId && event.data.frameId !== frameId) return;
      try {
        if (document.pictureInPictureElement && document.exitPictureInPicture)
          document.exitPictureInPicture().catch(function () {});
        for (const video of document.querySelectorAll('video'))
          if (video.webkitPresentationMode === 'picture-in-picture')
            video.webkitSetPresentationMode('inline');
      } catch (_) {}
      return;
    }
    if (!event.data || event.data.type !== 'slatePiPEnter') return;
    for (const frame of document.querySelectorAll('iframe')) {
      try { frame.contentWindow.postMessage(event.data, '*'); } catch (_) {}
    }
    if (event.data.frameId && event.data.frameId !== frameId) return;
    let video = choose();
    if (!video && event.data.manual) {
      let best = null, most = -1;
      for (const v of document.querySelectorAll('video')) {
        if (adCandidate(v)) continue;
        const box = v.getBoundingClientRect();
        if (box.width < 160 || box.height < 90) continue;
        let score = box.width * box.height;
        if (!v.paused && !v.ended) score += 1000000;
        if (!v.muted && v.volume > 0) score += 500000;
        if (score > most) { most = score; best = v; }
      }
      video = best;
    }
    if (!video) return;
    try {
      if (video.webkitPresentationMode === 'picture-in-picture' ||
          document.pictureInPictureElement === video) return;
      if (typeof video.webkitSetPresentationMode === 'function')
        video.webkitSetPresentationMode('picture-in-picture');
      else if (video.requestPictureInPicture) video.requestPictureInPicture().catch(function () {});
    } catch (_) {}
  });
  // Player replacements and in-stream ad markers need not emit a play/pause
  // event. Refresh frame state without letting another iframe close native PiP.
  if (typeof MutationObserver === 'function') {
    const observer = new MutationObserver(report);
    const root = document.documentElement || document.body;
    if (root) observer.observe(root, {childList:true, subtree:true, attributes:true,
      attributeFilter:['data-slate-ad-break']});
  }
  report();
})();
)JS";

} // namespace slate
