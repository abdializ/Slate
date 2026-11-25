// File purpose: Site-scoped, idle-scheduled memory optimizer for heavy media & live-chat sites
// (Kick, YouTube, Twitch, X/Twitter, Reddit). Injected in WKContentWorld.defaultClientWorld so
// page scripts cannot observe or conflict with it.
//
// Research basis:
// - Live chat DOM windowing prevents unbounded emote/message retention on Kick, Twitch, and YouTube Live.
// - Pausing far-offscreen feed preview <video> elements releases WebKit GPU decode surfaces on YouTube/X/Reddit.
// - Suspending muted background streams on visibilitychange halts hidden MSE/GPU decoding while keeping
//   audible background playback (music, podcasts, live audio) completely uninterrupted.

#pragma once

namespace slate {

inline constexpr const char* kMemoryOptimizerJs = R"JS(
(function() {
  'use strict';
  if (window.__slateMemoryOptimizerInstalled) return;
  window.__slateMemoryOptimizerInstalled = true;

  const host = (window.location && window.location.hostname ? window.location.hostname : '').toLowerCase();
  const isKick = host === 'kick.com' || host.endsWith('.kick.com');
  const isTwitch = host === 'twitch.tv' || host.endsWith('.twitch.tv');
  const isYouTube = host === 'youtube.com' || host.endsWith('.youtube.com');
  const isX = host === 'x.com' || host.endsWith('.x.com') || host === 'twitter.com' || host.endsWith('.twitter.com');
  const isReddit = host === 'reddit.com' || host.endsWith('.reddit.com');

  if (!isKick && !isTwitch && !isYouTube && !isX && !isReddit) return;

  const kMaxChatNodes = 140;
  const kMaxPrunePerPass = 60;

  function findScrollAncestor(el) {
    let cur = el;
    for (let depth = 0; cur && depth < 6; depth++) {
      if (cur.scrollHeight > cur.clientHeight + 20) return cur;
      cur = cur.parentElement;
    }
    return el;
  }

  function pruneChatContainer(container, maxKeep) {
    if (!container || !container.children || container.children.length <= maxKeep) return;
    const scroller = findScrollAncestor(container);
    if (scroller && scroller.scrollHeight > scroller.clientHeight + 20) {
      const distFromBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight;
      // Never prune while the user is scrolled up reading chat history.
      if (distFromBottom > 150) return;
    }
    const excess = Math.min(kMaxPrunePerPass, container.children.length - maxKeep);
    for (let i = 0; i < excess; i++) {
      const first = container.firstElementChild;
      if (!first) break;
      // Preserve pinned announcements or input headers if present.
      if (first.getAttribute && (first.getAttribute('data-pinned') === 'true' || first.tagName === 'STYLE')) break;
      first.remove();
    }
  }

  function pruneLiveChats() {
    try {
      if (isKick) {
        const selectors = [
          '#chatroom-messages .no-scrollbar > div',
          '#chatroom-messages [class*="overflow-y-scroll"] > div',
          '[id="chatroom-messages"] .relative > div'
        ];
        for (let i = 0; i < selectors.length; i++) {
          const el = document.querySelector(selectors[i]);
          if (el && el.children && el.children.length > kMaxChatNodes) {
            pruneChatContainer(el, kMaxChatNodes);
            break;
          }
        }
      } else if (isTwitch) {
        const container = document.querySelector('.chat-scrollable-area__message-container');
        if (container) pruneChatContainer(container, kMaxChatNodes);
      } else if (isYouTube) {
        const ytChat = document.querySelector('yt-live-chat-item-list-renderer #items');
        if (ytChat) pruneChatContainer(ytChat, kMaxChatNodes);
      }
    } catch (e) {}
  }

  function isPrimaryWatchVideo(video) {
    try {
      if (!video) return false;
      if (video.closest('#movie_player, .html5-video-player, [data-a-target="video-player"], #video-player, .video-js')) {
        return true;
      }
      const rect = video.getBoundingClientRect();
      // Treat large foreground players (>= 480px wide) as primary.
      if (rect.width >= 480 && rect.height >= 260) return true;
    } catch (e) {}
    return false;
  }

  function isVideoInPiP(video) {
    try {
      if (document.pictureInPictureElement === video) return true;
      if (video.webkitPresentationMode === 'picture-in-picture') return true;
    } catch (e) {}
    return false;
  }

  function pruneOffscreenPreviewVideos() {
    if (document.hidden) return;
    try {
      const vh = window.innerHeight || 900;
      const videos = document.getElementsByTagName('video');
      for (let i = 0; i < videos.length; i++) {
        const v = videos[i];
        if (!v || v.paused || isVideoInPiP(v) || isPrimaryWatchVideo(v)) continue;
        // Never touch audible media.
        if (!v.muted && v.volume > 0) continue;
        const rect = v.getBoundingClientRect();
        if (rect.bottom < -vh * 2.2 || rect.top > vh * 3.2) {
          v.pause();
        }
      }
    } catch (e) {}
  }

  function handleVisibilityChange() {
    try {
      const videos = document.getElementsByTagName('video');
      if (document.hidden) {
        for (let i = 0; i < videos.length; i++) {
          const v = videos[i];
          if (!v || v.paused || v.ended || isVideoInPiP(v)) continue;
          // Suspend ONLY muted streams in background tabs; audible playback continues untouched.
          if (v.muted || v.volume === 0) {
            v.__slateBgPaused = true;
            v.pause();
          }
        }
      } else {
        for (let i = 0; i < videos.length; i++) {
          const v = videos[i];
          if (v && v.__slateBgPaused) {
            v.__slateBgPaused = false;
            if (v.paused && !v.ended) {
              const p = v.play();
              if (p && typeof p.catch === 'function') p.catch(function() {});
            }
          }
        }
      }
    } catch (e) {}
  }

  function runIdlePass() {
    pruneLiveChats();
    pruneOffscreenPreviewVideos();
  }

  function scheduleIdlePass() {
    if (typeof window.requestIdleCallback === 'function') {
      window.requestIdleCallback(runIdlePass, { timeout: 2000 });
    } else {
      setTimeout(runIdlePass, 50);
    }
  }

  // Expose manual trim hook for Slate's native trim_memory() under memory pressure.
  window.__slateTrimPageMemory = function() {
    runIdlePass();
  };

  document.addEventListener('visibilitychange', handleVisibilityChange, true);
  // Gentle 12-second idle sweep — zero rAF work, zero impact on video frame pacing.
  setInterval(function() {
    if (!document.hidden) scheduleIdlePass();
  }, 12000);
})();
)JS";

} // namespace slate
