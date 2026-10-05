#import "engine/webkit_shields.h"
#include "engine/stealth_js.h"
#include <fstream>
#include <sstream>
#include <regex>
#include <algorithm>
#include <unordered_set>

namespace slate {

static NSString* const kSlateContentRuleListIdentifier = @"SlateShieldsV14";

static NSString* const kYahooAdDefuserSource = @R"JS(
(function() {
  'use strict';
  if (window.__slate_yahoo_defuser_installed__) return;
  window.__slate_yahoo_defuser_installed__ = true;

  try {
    const style = document.createElement('style');
    style.id = '__slate_yahoo_shield_css__';
    style.textContent = `
      #Slot300_250_1, #Slot300_250_2, #Slot300_600, [id^="Slot300_"],
      [data-test-id="right-rail-ad"], [data-test-id="right-rail-ad-container"],
      [data-test-id="right-rail-ad-frame"], [data-test-id="right-rail-slot"],
      [data-test-id="ad-slot"], [data-test-id="search-ad"], [data-test-id="message-ad"],
      div[class*="right-rail-ad"], div[class*="ad-rail"], div[class*="rightRailAd"],
      div[class*="ad-wrapper"], div[class*="ad_wrapper"],
      .slot-300-250, .slot-300-600, .uh-dmos-wrapper, .uh-dmos-overlay,
      [data-test-id="right-rail"] iframe,
      div[class*="video-dock"], div[class*="docked-player"], div[class*="docked-video"],
      div[class*="floating-video"], div[class*="floating-player"], div[class*="mini-player"],
      div[class*="sticky-player"], div[class*="ymail-video"], div[class*="news-video"],
      div[class*="outstream"], div[id*="outstream"],
      div[id*="video-dock"], div[id*="docked-player"], div[id*="docked-video"],
      div[id*="floating-video"], div[id*="floating-player"], div[id*="mini-player"],
      div[id*="sticky-player"] {
        display: none !important;
        visibility: hidden !important;
        height: 0 !important;
        width: 0 !important;
        max-height: 0 !important;
        max-width: 0 !important;
        min-height: 0 !important;
        min-width: 0 !important;
        opacity: 0 !important;
        pointer-events: none !important;
        overflow: hidden !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  } catch(e) {}

  function cleanYahooAds() {
    try {
      const selectors = [
        '#Slot300_250_1', '#Slot300_250_2', '#Slot300_600', '[id^="Slot300_"]',
        '[data-test-id="right-rail-ad"]', '[data-test-id="right-rail-ad-container"]',
        '[data-test-id="right-rail-ad-frame"]', '[data-test-id="right-rail-slot"]',
        '[data-test-id="ad-slot"]', '[data-test-id="search-ad"]', '[data-test-id="message-ad"]',
        'div[class*="right-rail-ad"]', 'div[class*="ad-rail"]', 'div[class*="rightRailAd"]',
        'div[class*="ad-wrapper"]', 'div[class*="ad_wrapper"]',
        '.slot-300-250', '.slot-300-600', '.uh-dmos-wrapper', '.uh-dmos-overlay',
        'div[class*="video-dock"]', 'div[class*="docked-player"]', 'div[class*="docked-video"]',
        'div[class*="floating-video"]', 'div[class*="floating-player"]', 'div[class*="mini-player"]',
        'div[class*="sticky-player"]', 'div[class*="ymail-video"]', 'div[class*="news-video"]',
        'div[class*="outstream"]', 'div[id*="outstream"]',
        'div[id*="video-dock"]', 'div[id*="docked-player"]', 'div[id*="docked-video"]',
        'div[id*="floating-video"]', 'div[id*="floating-player"]', 'div[id*="mini-player"]',
        'div[id*="sticky-player"]'
      ];
      const found = document.querySelectorAll(selectors.join(','));
      for (let i = 0; i < found.length; i++) {
        const el = found[i];
        if (!el) continue;
        const vids = el.getElementsByTagName('video');
        for (let j = 0; j < vids.length; j++) {
          try {
            vids[j].pause();
            vids[j].muted = true;
            vids[j].src = '';
          } catch(e) {}
        }
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('height', '0px', 'important');
        el.style.setProperty('width', '0px', 'important');
      }
    } catch(e) {}
  }

  cleanYahooAds();
  try {
    const obs = new MutationObserver(cleanYahooAds);
    obs.observe(document.documentElement || document.body, { childList: true, subtree: true });
  } catch(e) {}
  setInterval(cleanYahooAds, 1000);
})();
)JS";

static NSString* const kStreamAdDefuserSource = @R"JS(
(function() {
  'use strict';
  if (document.contentType === 'application/pdf' || (window.location && window.location.pathname && window.location.pathname.endsWith('.pdf'))) return;
  if (window.__slate_pie_defuser_installed__) return;
  window.__slate_pie_defuser_installed__ = true;

  // 1. Safe Deep Object Pruner (Pie Adblock & uBlock Origin engine)
  function deepPrune(obj, path) {
    if (!obj || typeof obj !== 'object') return;
    const segs = path.split('.');
    function recurse(curr, idx) {
      if (!curr || typeof curr !== 'object') return;
      const seg = segs[idx];
      const isLast = (idx === segs.length - 1);
      if (isLast) {
        if (seg === '*') {
          for (const k in curr) {
            if (Object.prototype.hasOwnProperty.call(curr, k)) delete curr[k];
          }
        } else if (Object.prototype.hasOwnProperty.call(curr, seg)) {
          delete curr[seg];
        }
        return;
      }
      if (seg === '[-]' && Array.isArray(curr)) {
        for (let i = curr.length - 1; i >= 0; i--) {
          recurse(curr[i], idx + 1);
        }
      } else if (seg === '[]' && Array.isArray(curr)) {
        for (let i = 0; i < curr.length; i++) {
          recurse(curr[i], idx + 1);
        }
      } else if (seg === '*' || seg === '{}') {
        for (const k of Object.keys(curr)) {
          recurse(curr[k], idx + 1);
        }
      } else if (Object.prototype.hasOwnProperty.call(curr, seg)) {
        recurse(curr[seg], idx + 1);
      }
    }
    recurse(obj, 0);
  }

  function pruneObject(obj, paths) {
    if (!obj || typeof obj !== 'object') return obj;
    for (let i = 0; i < paths.length; i++) {
      deepPrune(obj, paths[i]);
    }
    return obj;
  }

  // Common SSAI and Ad metadata keys across streaming platforms
  const kMaxPrunePaths = [
    'ssaiInfo',
    'fallback.ssaiInfo',
    'adtech-brightline',
    'adtech-google-pal',
    'adtech-iab-om'
  ];

  const kYouTubePrunePaths = [
    'adPlacements',
    'adSlots',
    'playerAds',
    'adBreakHeartbeatParams',
    'playerResponse.adPlacements',
    'playerResponse.adSlots',
    'playerResponse.playerAds',
    'playerResponse.adBreakHeartbeatParams',
    '[].playerResponse.adPlacements',
    '[].playerResponse.adSlots',
    '[].playerResponse.playerAds',
    'reelWatchSequenceResponse.entries.[-].command.reelWatchEndpoint.adClientParams.isAd'
  ];

  const kHuluPrunePaths = [
    'breaks',
    'custom_breaks_data',
    'pause_ads',
    'video_metadata.end_credits_time'
  ];

  function pruneStreamingJson(obj) {
    if (!obj || typeof obj !== 'object') return obj;

    // Max / HBO Max SSAI ad pods & adtech metadata pruning (Pie Adblock: ssaiInfo fallback.ssaiInfo)
    if ('ssaiInfo' in obj) {
      delete obj.ssaiInfo;
    }
    if (obj.fallback && typeof obj.fallback === 'object' && 'ssaiInfo' in obj.fallback) {
      delete obj.fallback.ssaiInfo;
    }
    if ('adtech-brightline' in obj) delete obj['adtech-brightline'];
    if ('adtech-google-pal' in obj) delete obj['adtech-google-pal'];
    if ('adtech-iab-om' in obj) delete obj['adtech-iab-om'];

    // YouTube ad metadata pruning
    if ('adPlacements' in obj) delete obj.adPlacements;
    if ('adSlots' in obj) delete obj.adSlots;
    if ('playerAds' in obj) delete obj.playerAds;
    if ('adBreakHeartbeatParams' in obj) delete obj.adBreakHeartbeatParams;
    if (obj.playerResponse && typeof obj.playerResponse === 'object') {
      pruneStreamingJson(obj.playerResponse);
    }

    // Disney+ SSAI manifest pruning
    if (obj.stream && typeof obj.stream === 'object') {
      if ('insertion' in obj.stream) delete obj.stream.insertion;
      if (Array.isArray(obj.stream.sources)) {
        for (let i = 0; i < obj.stream.sources.length; i++) {
          const src = obj.stream.sources[i];
          if (src && typeof src === 'object' && 'insertion' in src) delete src.insertion;
        }
      }
    }
    if ('pods' in obj && Array.isArray(obj.pods)) obj.pods = [];
    if ('ads' in obj && Array.isArray(obj.ads)) obj.ads = [];

    // Hulu & Peacock ad break pruning
    if ('breaks' in obj && Array.isArray(obj.breaks)) obj.breaks = [];
    if ('pause_ads' in obj) delete obj.pause_ads;

    return obj;
  }

  // 2. Hook window.fetch (Pie Adblock json-prune-fetch-response)
  try {
    if (typeof window.fetch === 'function') {
      const origFetch = window.fetch;
      window.fetch = function(...args) {
        const url = (args[0] instanceof Request) ? args[0].url : String(args[0] || '');
        const needsPrune = url.includes('playbackInfo') ||
                           url.includes('/player') ||
                           url.includes('/get_watch') ||
                           url.includes('/playlist') ||
                           url.includes('bamgrid.com') ||
                           url.includes('disney') ||
                           url.includes('ad-pod') ||
                           url.includes('ssai');

        const p = origFetch.apply(this, args);
        if (!needsPrune) return p;

        return p.then(res => {
          if (!res || !res.ok) return res;
          try {
            return res.clone().json().then(data => {
              if (data && typeof data === 'object') {
                pruneStreamingJson(data);
                const prunedRes = Response.json(data, {
                  status: res.status,
                  statusText: res.statusText,
                  headers: res.headers
                });
                Object.defineProperties(prunedRes, {
                  ok: { value: res.ok },
                  redirected: { value: res.redirected },
                  type: { value: res.type },
                  url: { value: res.url }
                });
                return prunedRes;
              }
              return res;
            }).catch(() => res);
          } catch(e) {
            return res;
          }
        });
      };
      window.fetch.toString = () => origFetch.toString();
    }
  } catch(e) {}

  // 3. Hook Response.prototype.json (Pie Adblock json-prune)
  try {
    if (typeof Response !== 'undefined' && Response.prototype && Response.prototype.json) {
      const origJson = Response.prototype.json;
      Response.prototype.json = function() {
        return origJson.apply(this, arguments).then(data => {
          if (data && typeof data === 'object') {
            pruneStreamingJson(data);
          }
          return data;
        });
      };
      Response.prototype.json.toString = () => origJson.toString();
    }
  } catch(e) {}

  // 3. Hook JSON.parse (Pie Adblock json-prune)
  try {
    const origParse = JSON.parse;
    JSON.parse = function(text, reviver) {
      const res = origParse.apply(this, arguments);
      if (res && typeof res === 'object') {
        pruneStreamingJson(res);
      }
      return res;
    };
    JSON.parse.toString = () => origParse.toString();
  } catch(e) {}

  // 4. Hook XMLHttpRequest (Safe Pie Adblock pattern)
  try {
    if (typeof XMLHttpRequest !== 'undefined') {
      const matchedRequests = new WeakSet();
      const origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        if (typeof url === 'string' && (url.includes('playbackInfo') || url.includes('/player') || url.includes('/get_watch') || url.includes('bamgrid.com') || url.includes('disney') || url.includes('ad-pod') || url.includes('ssai'))) {
          matchedRequests.add(this);
        }
        return origOpen.apply(this, arguments);
      };

      const origResponseGetter = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'response')?.get;
      const origResponseTextGetter = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'responseText')?.get;

      if (origResponseGetter) {
        Object.defineProperty(XMLHttpRequest.prototype, 'response', {
          get: function() {
            const raw = origResponseGetter.call(this);
            if (!matchedRequests.has(this) || !raw) return raw;
            try {
              if (typeof raw === 'object') {
                pruneStreamingJson(raw);
                return raw;
              } else if (typeof raw === 'string') {
                const parsed = JSON.parse(raw);
                pruneStreamingJson(parsed);
                return (this.responseType === 'json') ? parsed : JSON.stringify(parsed);
              }
            } catch(e) {}
            return raw;
          },
          configurable: true,
          enumerable: true
        });
      }

      if (origResponseTextGetter) {
        Object.defineProperty(XMLHttpRequest.prototype, 'responseText', {
          get: function() {
            const raw = origResponseTextGetter.call(this);
            if (!matchedRequests.has(this) || !raw) return raw;
            try {
              const parsed = JSON.parse(raw);
              pruneStreamingJson(parsed);
              return JSON.stringify(parsed);
            } catch(e) {}
            return raw;
          },
          configurable: true,
          enumerable: true
        });
      }
    }
  } catch(e) {}


  try {
    // YouTube initial player response ad stripping
    let ytInitialVal = undefined;
    Object.defineProperty(window, 'ytInitialPlayerResponse', {
      get: () => ytInitialVal,
      set: (val) => {
        if (val && typeof val === 'object') {
          pruneObject(val, kYouTubePrunePaths);
        }
        ytInitialVal = val;
      },
      configurable: true,
      enumerable: true
    });
  } catch(e) {}

  // Click only explicit ad-skip controls. Intro/recap controls belong to the show.
  const kSkipSelectors = [
    '[data-testid="player-skip-ad"]',
    '[data-testid="skip-ad-button"]',
    'button[aria-label*="skip ad" i]',
    'button[aria-label*="skip advertisement" i]',
    '.ytp-ad-skip-button',
    '.ytp-ad-skip-button-modern',
    '.ytp-skip-ad-button',
    '.vjs-skip-ad',
    'button[class*="AdSkip"]',
    'button[class*="skipAd"]'
  ];

  function isElementVisible(el) {
    if (!el) return false;
    try {
      if (typeof el.checkVisibility === 'function') {
        if (!el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) return false;
      }
      const style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity) < 0.1 || style.pointerEvents === 'none') {
        return false;
      }
      const rect = el.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return false;
    } catch(e) { return false; }
    return true;
  }

  function isStreamingPlatform() {
    const host = (window.location && window.location.hostname) ? window.location.hostname.toLowerCase() : '';
    return host.includes('max.com') || host.includes('hbomax.com') ||
           host.includes('disneyplus.com') || host.includes('hulu.com') ||
           host.includes('peacocktv.com') || host.includes('paramountplus.com') ||
           host.includes('youtube.com') || host.includes('twitch.tv') ||
           host.includes('kick.com') || host.includes('crunchyroll.com') ||
           host.includes('tubitv.com') || host.includes('pluto.tv');
  }

  function triggerSkipButtons() {
    if (!isStreamingPlatform()) return;
    const q = kSkipSelectors.join(',');
    let buttons;
    try {
      buttons = document.querySelectorAll(q);
    } catch(e) { return; }

    const now = Date.now();
    for (let i = 0; i < buttons.length; i++) {
      const btn = buttons[i];
      if (!btn) continue;
      // Never click if clicked recently (prevent resetting player idle timer)
      if (btn.__slate_last_clicked && (now - btn.__slate_last_clicked < 4000)) continue;
      if (!isElementVisible(btn)) continue;

      const text = ((btn.textContent || '') + ' ' + (btn.getAttribute('aria-label') || '') + ' ' + (btn.className || '')).toLowerCase();
      // Never click seek buttons (e.g. forward 10s, backward 15s, skip ahead, skip back, etc.)
      if (/\b(5|10|15|30)\s*(s|sec|second)/.test(text) || text.includes('jump') || text.includes('forward') || text.includes('backward') || text.includes('rewind') || text.includes('ahead') || text.includes('back')) {
        continue;
      }
      const explicitAdControl = /skip\s*(ad|advertisement)/.test(text) ||
        /ad\s*skip/.test(text) || btn.matches('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .vjs-skip-ad');
      if (explicitAdControl && !btn.disabled && btn.getAttribute('aria-disabled') !== 'true') {
        btn.__slate_last_clicked = now;
        try { btn.click(); } catch(e) {}
      }
    }
  }

  // 7. Under-The-Hood Streaming Ad Detection (Max, Disney+, Hulu, Peacock, Paramount+, YouTube)
  function anyVisibleAdIndicator(selector) {
    return Array.from(document.querySelectorAll(selector)).some(isElementVisible);
  }
  function checkAdActive() {
    if (!isStreamingPlatform()) return false;
    const host = window.location.hostname.toLowerCase();

    // Max / HBO Max ad indicators
    if (host.includes('max.com') || host.includes('hbomax.com')) {
      if (anyVisibleAdIndicator(
        '[data-testid*="ad-countdown"], [data-testid*="ad-break"], [data-testid*="ad-indicator"], ' +
        '[class*="AdCountdown"], [class*="AdBadge"], [class*="AdPod"], [class*="AdIndicator"], ' +
        '[aria-label*="advertisement" i], [aria-label*="ad 1 of" i], [aria-label*="ad 2 of" i]'
      )) return true;
    }

    // Disney+ ad indicators
    if (host.includes('disneyplus.com')) {
      if (anyVisibleAdIndicator(
        '[class*="ad-timer"], [class*="ad-badge"], [class*="ad-countdown"], [class*="ad-banner"], ' +
        '[aria-label*="advertisement" i]'
      )) return true;
    }

    // Hulu ad indicators
    if (host.includes('hulu.com')) {
      if (anyVisibleAdIndicator(
        '.ad-overlay, .ad-container, .ad-timer, [data-testid="ad-timer"], .ad-countdown, ' +
        '.ad-indicator, [class*="AdTimer"]'
      )) return true;
    }

    // Peacock & Paramount+ ad indicators
    if (host.includes('peacocktv.com') || host.includes('paramountplus.com')) {
      if (anyVisibleAdIndicator(
        '.video-player__ad-container, [class*="ad-badge"], [class*="adCountdown"], ' +
        '[class*="adTimer"], .ad-container, .ad-label, .ad-countdown, [class*="ad-pod"]'
      )) return true;
    }

    // YouTube ad indicators
    if (host.includes('youtube.com')) {
      if (anyVisibleAdIndicator('#movie_player.ad-showing, #movie_player.ad-interrupting, .html5-video-player.ad-showing')) return true;
      if (anyVisibleAdIndicator('.ytp-ad-player-overlay, .ytp-ad-text')) return true;
    }

    // Twitch live streams cannot generally be accelerated; use only player ad UI signals.
    if (host.includes('twitch.tv')) {
      if (anyVisibleAdIndicator('[data-a-target="video-ad-label"], [data-test-selector="ad-banner-default-text"], [data-a-target="ad-countdown"]')) return true;
    }

    // Generic streaming ad countdown / badge overlay
    if (anyVisibleAdIndicator(
      '[class*="AdCountdown-"], [class*="AdBadge-"], [class*="AdPod-"], [class*="ad-timer"], [class*="ad-indicator"]'
    )) return true;

    return false;
  }

  // 8. Silent Ad Acceleration & Auto-Mute (Pie Adblock clean stream defuser)
  // Cuts through unskippable ad breaks at 16x silently; NEVER seeks currentTime on main content
  function handleStreamingAdVideo(video) {
    if (!video) return;
    if (!isStreamingPlatform()) {
      if (video.__slate_ad_boosted__) {
        video.__slate_ad_boosted__ = false;
        video.muted = video.__slate_orig_muted__;
        try { video.playbackRate = video.__slate_orig_rate__ || 1.0; } catch(e) {}
      }
      return;
    }

    const adActive = checkAdActive();

    // DOM state is shared with Slate’s isolated media monitor; an ad on the
    // show’s video element must not become a fresh automatic PiP candidate.
    if (video.setAttribute && video.removeAttribute) {
      if (adActive) {
        if (!video.hasAttribute("data-slate-ad-break")) video.setAttribute("data-slate-ad-break", "1");
      } else video.removeAttribute("data-slate-ad-break");
    }
    if (adActive) {
      if (video.paused || video.ended) return;
      if (!video.__slate_ad_boosted__) {
        video.__slate_ad_boosted__ = true;
        video.__slate_orig_rate__ = video.playbackRate || 1.0;
        video.__slate_orig_muted__ = video.muted;
      }
      if (!video.muted) video.muted = true;
      // A live stream has no finite ad segment to fast-forward through.
      if (!window.location.hostname.endsWith('twitch.tv') && video.playbackRate !== 16.0) {
        try { video.playbackRate = 16.0; } catch(e) {}
      }
    } else if (video.__slate_ad_boosted__) {
      video.__slate_ad_boosted__ = false;
      video.muted = video.__slate_orig_muted__;
      try { video.playbackRate = video.__slate_orig_rate__ || 1.0; } catch(e) {}
    }
  }

  function scanMedia() {
    triggerSkipButtons();
    const videos = document.getElementsByTagName('video');
    for (let i = 0; i < videos.length; i++) {
      const v = videos[i];
      handleStreamingAdVideo(v);
    }
  }

  // Debounced Skip Button MutationObserver
  try {
    let obsTimer = 0;
    const obs = new MutationObserver(function() {
      if (obsTimer) return;
      obsTimer = setTimeout(function() {
        obsTimer = 0;
        scanMedia();
      }, 100);
    });
    const target = document.body || document.documentElement;
    if (target) {
      obs.observe(target, { childList: true, subtree: true, attributes: true,
        attributeFilter: ["class", "data-testid", "aria-label", "hidden", "style"] });
    } else {
      document.addEventListener('DOMContentLoaded', function() {
        if (document.body) obs.observe(document.body, { childList: true, subtree: true, attributes: true,
            attributeFilter: ["class", "data-testid", "aria-label", "hidden", "style"] });
      });
    }
  } catch(e) {}

  setInterval(scanMedia, 1000);
  document.addEventListener('play', scanMedia, true);
  document.addEventListener('loadedmetadata', scanMedia, true);
  document.addEventListener('resize', scanMedia, true);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scanMedia);
  } else {
    scanMedia();
  }
})();
)JS";

static NSString* const kGlobalBlockerKey = @"SlateAdBlockGlobalEnabled";
static NSString* const kAllowedSitesKey = @"SlateAdBlockAllowedSites";

static NSString* NormalizedSite(NSString* host) {
  NSString* normalized = [[host lowercaseString] stringByTrimmingCharactersInSet:
    [NSCharacterSet characterSetWithCharactersInString:@". "]];
  if ([normalized hasPrefix:@"www."]) normalized = [normalized substringFromIndex:4];
  return normalized;
}

static bool ValidFilterDomain(const std::string& domain) {
  if (domain.empty() || domain.size() > 253 || domain.front()=='.' || domain.back()=='.') return false;
  return std::all_of(domain.begin(), domain.end(), [](unsigned char c) {
    return (c>='a' && c<='z') || (c>='A' && c<='Z') ||
      (c>='0' && c<='9') || c=='.' || c=='-';
  });
}

WebKitShields& WebKitShields::Shared() {
  static WebKitShields s_instance;
  return s_instance;
}

WebKitShields::WebKitShields() {
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  enabled_ = [defaults objectForKey:kGlobalBlockerKey] ? [defaults boolForKey:kGlobalBlockerKey] : true;
  disabled_sites_ = [NSMutableSet setWithArray:[defaults stringArrayForKey:kAllowedSitesKey] ?: @[]];
  controller_hosts_ = [NSMapTable weakToStrongObjectsMapTable];
  NSString* stealthSource = [NSString stringWithUTF8String:slate::kStealthJs];
  stealth_script_ = [[WKUserScript alloc] initWithSource:stealthSource
                                           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                        forMainFrameOnly:NO];
}

void WebKitShields::Initialize(const std::vector<std::string>& rule_file_paths) {
  const std::vector<std::string> paths = rule_file_paths;
  uint64_t fingerprint = 1469598103934665603ULL;
  for (const auto& path : rule_file_paths) {
    NSString* file = [NSString stringWithUTF8String:path.c_str()];
    for (unsigned char byte : std::string(file.lastPathComponent.UTF8String)) {
      fingerprint ^= byte;
      fingerprint *= 1099511628211ULL;
    }
    std::ifstream input(path,std::ios::binary);
    char buffer[8192];
    while (input.read(buffer,sizeof(buffer)) || input.gcount()>0) {
      for (std::streamsize i=0;i<input.gcount();++i) {
        fingerprint ^= static_cast<unsigned char>(buffer[i]);
        fingerprint *= 1099511628211ULL;
      }
    }
    fingerprint ^= 0xff;
    fingerprint *= 1099511628211ULL;
  }
  rule_identifier_ = [NSString stringWithFormat:@"%@-%016llx", kSlateContentRuleListIdentifier,
    static_cast<unsigned long long>(fingerprint)];
  NSString* appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  NSString* storePath = NSProcessInfo.processInfo.environment[@"SLATE_SHIELDS_CACHE_DIR"];
  if (!storePath.isAbsolutePath) storePath = [appSupport stringByAppendingPathComponent:@"Slate/ContentRuleLists"];
  [[NSFileManager defaultManager] createDirectoryAtPath:storePath withIntermediateDirectories:YES attributes:nil error:nil];
  NSURL* storeURL = [NSURL fileURLWithPath:storePath];
  store_ = [WKContentRuleListStore storeWithURL:storeURL];

  // 1. Check if compiled rule list is already in persistent store cache
  [store_ lookUpContentRuleListForIdentifier:rule_identifier_
                           completionHandler:^(WKContentRuleList* list, NSError* error) {
    if (list) {
      this->rule_list_ = list;
      this->compiled_rule_count_ = [NSUserDefaults.standardUserDefaults integerForKey:
        [@"SlateRuleCount-" stringByAppendingString:this->rule_identifier_]];
      fprintf(stderr, "[SlateShields] Loaded cached compiled rule list successfully.\n");
      this->BroadcastRuleList();
    } else {
      fprintf(stderr, "[SlateShields] No cached rule list, compiling in background...\n");
      this->CompileRules(paths);
    }
  }];
}

void WebKitShields::CompileRules(const std::vector<std::string>& rule_file_paths) {
  const std::vector<std::string> paths = rule_file_paths;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableArray* rules = [NSMutableArray array];

    // High-impact streaming and web video ad networks, SSAI/CSAI endpoints, VAST/VMAP servers
    NSArray* adDomains = @[
      // Google IMA / DAI / DoubleClick / AdSense
      @"dai.google.com",
      @"imasdk.googleapis.com",
      @"pubads.g.doubleclick.net",
      @"pagead2.googlesyndication.com",
      @"adservice.google.com",
      @"googleads.g.doubleclick.net",
      @"securepubads.g.doubleclick.net",
      @"video-ad-stats.googlesyndication.com",
      @"doubleclick.net",
      @"googlesyndication.com",
      @"googleadservices.com",
      @"2mdn.net",
      @"adssettings.google.com",
      @"fundingchoicesmessages.google.com",
      @"tpc.googlesyndication.com",
      // Yahoo Mail & Yahoo ad network
      @"gpt.mail.yahoo.net",
      @"ads.yahoo.com",
      @"gemini.yahoo.com",
      @"beap.gemini.yahoo.com",
      @"adtech.yahooinc.com",
      @"ybp.yahoo.com",
      @"fc.yahoo.com",
      @"mbid.yahoo.com",
      @"bats.video.yahoo.com",
      @"geo.yahoo.com",
      // Outstream & Floating Video Ad Platforms
      @"connatix.com",
      @"aniview.com",
      @"primis.tech",
      @"anyclip.com",
      @"vrtcal.com",
      @"playwire.com",
      @"seedtag.com",
      @"nativo.com",
      @"undertone.com",
      @"teads.tv",
      @"teads.com",
      @"admanmedia.com",
      @"exelator.com",
      @"liveramp.com",
      @"id5-sync.com",
      @"crwdcntrl.net",
      @"turn.com",
      // Innovid
      @"innovid.com",
      @"s.innovid.com",
      // SpringServe
      @"springserve.com",
      @"tv.springserve.com",
      // SpotX / Magnite / Rubicon
      @"spotxchange.com",
      @"spotx.tv",
      @"rubiconproject.com",
      @"telaria.com",
      @"magnite.com",
      // Flashtalking
      @"flashtalking.com",
      // Tremor Video / Unruly
      @"tremorhub.com",
      @"unruly.co",
      // Ad beacons / measurement / analytics
      @"imrworldwide.com",
      @"scorecardresearch.com",
      @"quantserve.com",
      @"moatads.com",
      @"adsafeprotected.com",
      // Streaming platform ad endpoints
      @"ads.hulu.com",
      @"ad.hulu.com",
      @"ad.peacocktv.com",
      @"ad-delivery.net",
      // Amazon video ad system
      @"amazon-adsystem.com",
      @"aax.amazon-adsystem.com",
      // Web ad networks
      @"criteo.com",
      @"criteo.net",
      @"outbrain.com",
      @"taboola.com",
      @"adnxs.com",
      @"adtechus.com",
      @"advertising.com",
      @"pubmatic.com",
      @"openx.net",
      @"casalemedia.com",
      @"telemetry.twitch.tv",
      @"spade.twitch.tv",
      @"inmobi.com",
      @"media.net",
      @"rlcdn.com",
      @"adroll.com",
      @"smartadserver.com",
      @"bidswitch.net",
      @"serving-sys.com",
      @"exponential.com",
      @"sovrn.com",
      @"contextweb.com",
      @"triplelift.com",
      @"3lift.com",
      @"yieldmo.com",
      @"cootlogix.com",
      @"indexww.com",
      @"gumgum.com",
      @"sharethrough.com",
      @"applovin.com",
      @"unityads.unity3d.com",
      @"ironsrc.com",
      @"revcontent.com",
      @"zergnet.com",
      @"infolinks.com",
      @"bidvertiser.com",
      @"adkernel.com",
      @"sonobi.com",
      @"districtm.io",
      @"yieldlab.net",
      @"smaato.net",
      @"richaudience.com"
    ];

    for (NSString* domain in adDomains) {
      NSString* escaped = [domain stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
      NSString* regex = [NSString stringWithFormat:@"^https?://+([^:/]+\\.)?%@([:/].*)?$", escaped];
      [rules addObject:@{
        @"trigger": @{ @"url-filter": regex },
        @"action": @{ @"type": @"block" }
      }];
    }

    // Parse the safe native subset. Unknown modifiers never become broader rules.
    size_t count = 0;
    const size_t kMaxRulesPerList = 20000;
    size_t unsupported = 0, duplicate = 0, raw = 0;
    std::unordered_set<std::string> seen;
    NSMutableArray* exceptionRules = [NSMutableArray array];

    for (const auto& path : paths) {
      std::ifstream infile(path);
      if (!infile.is_open()) continue;
      size_t listCount = 0;

      std::string line;
      while (std::getline(infile, line) && listCount < kMaxRulesPerList) {
        if (line.empty() || line[0] == '!' || line[0] == '[') continue;
        ++raw;
        if (line.size() > 4096) { ++unsupported; continue; }
        const bool exception = line.rfind("@@||",0)==0;
        const size_t start = exception ? 4 : 2;
        if (line.rfind("||",0)!=0 && !exception) { ++unsupported; continue; }
        const size_t end = line.find('^',start);
        if (end==std::string::npos) { ++unsupported; continue; }
        const std::string domain = line.substr(start,end-start);
        if (!ValidFilterDomain(domain)) { ++unsupported; continue; }
        const size_t dollar = line.find('$',end+1);
        if (end+1 < line.size() && dollar!=end+1) { ++unsupported; continue; }
        NSMutableDictionary* trigger = [NSMutableDictionary dictionary];
        NSString* nsDomain = [NSString stringWithUTF8String:domain.c_str()];
        NSString* escaped = [nsDomain stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
        trigger[@"url-filter"] = [NSString stringWithFormat:@"^https?://+([^:/]+\\.)?%@([:/].*)?$",escaped];
        NSMutableArray* types = [NSMutableArray array];
        bool supported = true;
        if (dollar!=std::string::npos) {
          std::stringstream options(line.substr(dollar+1));
          std::string option;
          while (std::getline(options,option,',')) {
            if (option=="third-party") trigger[@"load-type"] = @[@"third-party"];
            else if (option=="~third-party") trigger[@"load-type"] = @[@"first-party"];
            else if (option=="script") [types addObject:@"script"];
            else if (option=="image") [types addObject:@"image"];
            else if (option=="stylesheet") [types addObject:@"style-sheet"];
            else if (option=="font") [types addObject:@"font"];
            else if (option=="media") [types addObject:@"media"];
            else if (option=="xmlhttprequest") [types addObject:@"fetch"];
            else if (option=="websocket") [types addObject:@"websocket"];
            else if (option=="ping") [types addObject:@"ping"];
            else if (option=="popup") [types addObject:@"popup"];
            else if (option=="subdocument") [types addObject:@"child-document"];
            else if (option=="document") [types addObject:@"top-document"];
            else if (option.rfind("domain=",0)==0 && exception) {
              std::string site = option.substr(7);
              if (!ValidFilterDomain(site)) supported=false;
              else trigger[@"if-domain"] = @[[NSString stringWithFormat:@"*%@",[NSString stringWithUTF8String:site.c_str()]]];
            } else supported=false;
          }
        }
        if (!supported) { ++unsupported; continue; }
        if (types.count) trigger[@"resource-type"] = types;
        std::string key = line;
        if (!seen.insert(key).second) { ++duplicate; continue; }
        NSDictionary* converted = @{ @"trigger":trigger,
          @"action":@{ @"type":exception ? @"ignore-previous-rules" : @"block" } };
        if (exception) [exceptionRules addObject:converted];
        else { [rules addObject:converted]; ++count; ++listCount; }
      }
    }
    fprintf(stderr,"[SlateShields] raw=%zu native=%zu exceptions=%lu duplicates=%zu unsupported=%zu\n",
      raw,count,(unsigned long)exceptionRules.count,duplicate,unsupported);

    // Critical media exceptions (streaming CDNs, FairPlay DRM key servers, session & entitlement endpoints)
    NSArray* mediaExceptions = @[
      @"ytimg.com",
      @"googlevideo.com",
      @"youtube.com",
      @"youtu.be",
      @"ggpht.com",
      @"gvt1.com",
      @"gstatic.com",
      @"googleapis.com",
      @"twitch.tv",
      @"ttvnw.net",
      @"jtvnw.net",
      @"live-video.net",
      @"kick.com",
      @"kick-live.com",
      @"kick.stream",
      @"x.com",
      @"twitter.com",
      @"twimg.com",
      // Streaming / DRM services & CDNs (prevents EasyPrivacy blocking session/entitlement APIs & license servers)
      @"max.com",
      @"hbomax.com",
      @"hbo.com",
      @"discomax.com",
      @"h264.io",
      @"warnermediacdn.com",
      @"warnermedia.com",
      @"wbd.com",
      @"netflix.com",
      @"nflxvideo.net",
      @"nflximg.net",
      @"nflxext.com",
      @"disneyplus.com",
      @"bamgrid.com",
      @"disney-plus.net",
      @"hulu.com",
      @"hulustream.com",
      @"peacocktv.com",
      @"paramountplus.com",
      @"primevideo.com",
      @"amazonvideo.com",
      @"aiv-cdn.net",
      @"spotify.com",
      @"crunchyroll.com",
      @"tubitv.com",
      @"pluto.tv",
      @"fubo.tv",
      @"sling.com",
      @"starz.com",
      @"mgmplus.com",
      @"directv.com",
      @"sho.com",
      @"showtime.com",
      @"apple.com",
      @"appleid.apple.com"
    ];
    for (NSString* domain in mediaExceptions) {
      NSString* escaped = [domain stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
      NSString* regex = [NSString stringWithFormat:@"^https?://+([^:/]+\\.)?%@([:/].*)?$", escaped];
      [exceptionRules addObject:@{
        @"trigger": @{ @"url-filter": regex },
        @"action": @{ @"type": @"ignore-previous-rules" }
      }];
    }

    // Native WebKit Content Blocker cosmetic hiding rules (css-display-none)
    NSArray* cosmeticRuleGroups = @[
      // Group 1: Yahoo Mail & Yahoo Web: right rail ad pane, ad slots, and floating/docked video player
      @{
        @"trigger": @{
          @"url-filter": @".*",
          @"if-domain": @[ @"*mail.yahoo.com", @"*yahoo.com" ]
        },
        @"action": @{
          @"type": @"css-display-none",
          @"selector": @"#Slot300_250_1, #Slot300_250_2, #Slot300_600, [id^='Slot300_'], [data-test-id='right-rail-ad'], [data-test-id='right-rail-ad-container'], [data-test-id='right-rail-ad-frame'], [data-test-id='right-rail-slot'], [data-test-id='ad-slot'], [data-test-id='search-ad'], [data-test-id='message-ad'], div[class*='right-rail-ad'], div[class*='ad-rail'], div[class*='rightRailAd'], div[class*='ad-wrapper'], div[class*='ad_wrapper'], .slot-300-250, .slot-300-600, .uh-dmos-wrapper, .uh-dmos-overlay, [data-test-id='right-rail'] iframe, div[class*='video-dock'], div[class*='docked-player'], div[class*='docked-video'], div[class*='floating-video'], div[class*='floating-player'], div[class*='mini-player'], div[class*='sticky-player'], div[class*='ymail-video'], div[class*='news-video'], div[id*='video-dock'], div[id*='docked-player'], div[id*='docked-video'], div[id*='floating-video'], div[id*='floating-player'], div[id*='mini-player'], div[id*='sticky-player']"
        }
      },
      // Group 2: Web-wide floating, docked, and outstream video players
      @{
        @"trigger": @{ @"url-filter": @".*" },
        @"action": @{
          @"type": @"css-display-none",
          @"selector": @"div[class*='video-dock'], div[class*='docked-player'], div[class*='docked-video'], div[class*='floating-video'], div[class*='floating-player'], div[class*='mini-player'], div[class*='sticky-player'], div[class*='outstream'], div[id*='outstream'], [class*='connatix'], [id*='connatix'], connatix-player, [class*='primis'], [id*='primis'], [class*='aniview'], [id*='aniview'], [class*='anyclip'], [id*='anyclip'], anyclip-widget, [class*='vrtcal'], [class*='playwire'], [class*='seedtag'], [class*='teads-inread'], [class*='teads'], [class*='outstream-ad'], [class*='outstream-player'], [class*='floating-ad'], [class*='sticky-ad'], div[class*='video-card'][class*='ad'], div[class*='video-card'][class*='sponsored'], div[class*='vpaid']"
        }
      },
      // Group 3: Google Ads, DFP, AdSense, GPT containers and iframes
      @{
        @"trigger": @{ @"url-filter": @".*" },
        @"action": @{
          @"type": @"css-display-none",
          @"selector": @".adsbygoogle, [id^='google_ads_iframe'], [id^='google_ads_div'], [id^='div-gpt-ad'], [id^='gpt-ad'], [id^='gpt_unit'], [id^='dfp-ad'], [id^='dfp_ad'], iframe[id^='google_ads_'], iframe[id^='aswift_']"
        }
      },
      // Group 4: Taboola, Outbrain, and Sponsored widgets
      @{
        @"trigger": @{ @"url-filter": @".*" },
        @"action": @{
          @"type": @"css-display-none",
          @"selector": @"div[id^='taboola-'], div[class*='taboola-'], .trc_related_container, .trc_rbox_div, div[class*='OUTBRAIN'], div[id^='outbrain'], div[class*='outbrain'], div[class*='sponsored-post'], div[class*='sponsored-content'], div[class*='sponsor-ad'], div[class*='promoted-item']"
        }
      },
      // Group 5: Generic ad units, slots, banners, sidebars, placeholders
      @{
        @"trigger": @{ @"url-filter": @".*" },
        @"action": @{
          @"type": @"css-display-none",
          @"selector": @"div[class*='ad-container'], div[class*='ad-wrapper'], div[class*='ad-slot'], div[class*='ad-banner'], div[class*='ad-placeholder'], div[class*='ads-container'], div[class*='ads-wrapper'], div[class*='ads-slot'], div[class*='ad_container'], div[class*='ad_wrapper'], div[class*='ad_slot'], div[class*='ad-sidebar'], div[class*='ad-unit'], div[class*='ad-placement'], [data-ad-container], [data-ad-slot], [data-ad-unit]"
        }
      },
      // Group 6: YouTube ad overlays and promo slots
      @{
        @"trigger": @{
          @"url-filter": @".*",
          @"if-domain": @[ @"*youtube.com" ]
        },
        @"action": @{
          @"type": @"css-display-none",
          @"selector": @".ytp-ad-overlay-container, .ytp-ad-message-container, .ytp-ad-progress-list, ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer, ytd-promoted-video-renderer, ytd-display-ad-renderer, ytd-statement-banner-renderer, #masthead-ad, ytd-companion-ad-renderer"
        }
      }
    ];
    [rules addObjectsFromArray:cosmeticRuleGroups];

    // In WebKit Content Blockers, ignore-previous-rules must follow block rules
    [rules addObjectsFromArray:exceptionRules];

    NSError* jsonError = nil;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:rules options:0 error:&jsonError];
    if (jsonData && !jsonError) {
      NSString* jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

      dispatch_async(dispatch_get_main_queue(), ^{
        [this->store_ compileContentRuleListForIdentifier:this->rule_identifier_
                                   encodedContentRuleList:jsonString
                                        completionHandler:^(WKContentRuleList* list, NSError* compileError) {
          if (list) {
            this->rule_list_ = list;
            this->compiled_rule_count_ = rules.count;
            [NSUserDefaults.standardUserDefaults setInteger:rules.count forKey:
              [@"SlateRuleCount-" stringByAppendingString:this->rule_identifier_]];
            fprintf(stderr, "[SlateShields] Compiled %lu rules successfully.\n", (unsigned long)rules.count);
            this->BroadcastRuleList();
          } else {
            fprintf(stderr, "[SlateShields] Compilation failed: %s\n", compileError ? compileError.description.UTF8String : "unknown");
          }
        }];
      });
    }
  });
}

void WebKitShields::BroadcastRuleList() {
  if (!rule_list_) return;
  NSArray* controllersToUpdate = nil;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    controllersToUpdate = registered_controllers_ ? [registered_controllers_ allObjects] : @[];
  }
  fprintf(stderr, "[SlateShields] Attaching rule list to %lu active web views (enabled=%d).\n", (unsigned long)controllersToUpdate.count, (int)this->enabled_);
  dispatch_async(dispatch_get_main_queue(), ^{
    for (WKUserContentController* ctrl in controllersToUpdate) {
      if (ctrl) {
        @try {
          [ctrl removeAllContentRuleLists];
          NSString* site = [this->controller_hosts_ objectForKey:ctrl];
          if (this->enabled_ && ![this->disabled_sites_ containsObject:site] && this->rule_list_) {
            [ctrl addContentRuleList:this->rule_list_];
          }
        } @catch (id ex) {}
      }
    }
  });
}

void WebKitShields::ApplyToUserContentController(WKUserContentController* controller, bool incognito) {
  if (!controller) return;

  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!registered_controllers_) {
      registered_controllers_ = [NSHashTable weakObjectsHashTable];
    }
    [registered_controllers_ addObject:controller];
    [controller_hosts_ setObject:@"" forKey:controller];
  }

  // Ad filtering stays in the compiled WebKit list so both switches can detach it.

  // Apply stealth / anti-fingerprinting in incognito mode
  if (incognito) {
    [controller addUserScript:stealth_script_];
  }

  // Attach compiled rule list immediately if already available
  if (enabled_ && rule_list_) {
    @try {
      [controller addContentRuleList:rule_list_];
    } @catch (id ex) {}
  }
}

void WebKitShields::InjectStreamingProtection(WKWebView* webView) const {
  if (!webView || !enabled_) return;
  NSString* host = NormalizedSite(webView.URL.host ?: @"");
  if (!host.length || [disabled_sites_ containsObject:host]) return;
  NSArray<NSString*>* domains = @[@"max.com", @"hbomax.com", @"disneyplus.com",
    @"hulu.com", @"peacocktv.com", @"paramountplus.com", @"youtube.com",
    @"twitch.tv", @"kick.com", @"crunchyroll.com", @"tubitv.com", @"pluto.tv"];
  for (NSString* domain in domains) {
    if ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) {
      [webView evaluateJavaScript:kStreamAdDefuserSource completionHandler:nil];
      return;
    }
  }

  // Yahoo Mail: defuse floating docked video player and right-rail ad pane
  if ([host isEqualToString:@"mail.yahoo.com"] || [host hasSuffix:@".mail.yahoo.com"] ||
      [host isEqualToString:@"yahoo.com"] || [host hasSuffix:@".yahoo.com"]) {
    [webView evaluateJavaScript:kYahooAdDefuserSource completionHandler:nil];
    return;
  }
}

void WebKitShields::SetEnabled(bool enabled) {
  enabled_ = enabled;
  [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kGlobalBlockerKey];
  BroadcastRuleList();
}

bool WebKitShields::IsSiteEnabled(const std::string& host) const {
  NSString* site = NormalizedSite([NSString stringWithUTF8String:host.c_str()]);
  return !site.length || ![disabled_sites_ containsObject:site];
}

std::vector<std::string> WebKitShields::DisabledSites() const {
  std::vector<std::string> result;
  for (NSString* site in disabled_sites_) result.emplace_back(site.UTF8String);
  return result;
}

void WebKitShields::SetSiteEnabled(const std::string& host, bool enabled) {
  NSString* site = NormalizedSite([NSString stringWithUTF8String:host.c_str()]);
  if (!site.length) return;
  if (enabled) [disabled_sites_ removeObject:site];
  else [disabled_sites_ addObject:site];
  [NSUserDefaults.standardUserDefaults setObject:disabled_sites_.allObjects forKey:kAllowedSitesKey];
  BroadcastRuleList();
}

void WebKitShields::UpdateControllerForURL(WKUserContentController* controller, NSURL* url) {
  if (!controller) return;
  NSString* site = NormalizedSite(url.host ?: @"");
  [controller_hosts_ setObject:site forKey:controller];
  @try {
    [controller removeAllContentRuleLists];
    if (enabled_ && ![disabled_sites_ containsObject:site] && rule_list_)
      [controller addContentRuleList:rule_list_];
  } @catch (id ex) {}
}

bool WebKitShields::IsAdOrTrackerHost(NSString* host) const {
  if (!host || !host.length) return false;
  static NSSet<NSString*>* s_adDomains = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_adDomains = [NSSet setWithArray:@[
      @"dai.google.com",
      @"imasdk.googleapis.com",
      @"pubads.g.doubleclick.net",
      @"pagead2.googlesyndication.com",
      @"adservice.google.com",
      @"googleads.g.doubleclick.net",
      @"securepubads.g.doubleclick.net",
      @"video-ad-stats.googlesyndication.com",
      @"doubleclick.net",
      @"googlesyndication.com",
      @"googleadservices.com",
      @"2mdn.net",
      @"adssettings.google.com",
      @"fundingchoicesmessages.google.com",
      @"tpc.googlesyndication.com",
      @"gpt.mail.yahoo.net",
      @"ads.yahoo.com",
      @"gemini.yahoo.com",
      @"beap.gemini.yahoo.com",
      @"adtech.yahooinc.com",
      @"ybp.yahoo.com",
      @"fc.yahoo.com",
      @"mbid.yahoo.com",
      @"bats.video.yahoo.com",
      @"geo.yahoo.com",
      @"connatix.com",
      @"aniview.com",
      @"primis.tech",
      @"anyclip.com",
      @"vrtcal.com",
      @"playwire.com",
      @"seedtag.com",
      @"nativo.com",
      @"undertone.com",
      @"teads.tv",
      @"teads.com",
      @"admanmedia.com",
      @"exelator.com",
      @"liveramp.com",
      @"id5-sync.com",
      @"crwdcntrl.net",
      @"turn.com",
      @"innovid.com",
      @"s.innovid.com",
      @"springserve.com",
      @"tv.springserve.com",
      @"spotxchange.com",
      @"spotx.tv",
      @"rubiconproject.com",
      @"telaria.com",
      @"magnite.com",
      @"flashtalking.com",
      @"tremorhub.com",
      @"unruly.co",
      @"imrworldwide.com",
      @"scorecardresearch.com",
      @"quantserve.com",
      @"moatads.com",
      @"adsafeprotected.com",
      @"ads.hulu.com",
      @"ad.hulu.com",
      @"ad.peacocktv.com",
      @"ad-delivery.net",
      @"amazon-adsystem.com",
      @"aax.amazon-adsystem.com",
      @"criteo.com",
      @"criteo.net",
      @"outbrain.com",
      @"outbrain.net",
      @"taboola.com",
      @"adnxs.com",
      @"adtechus.com",
      @"advertising.com",
      @"pubmatic.com",
      @"openx.net",
      @"casalemedia.com",
      @"telemetry.twitch.tv",
      @"spade.twitch.tv",
      @"inmobi.com",
      @"media.net",
      @"rlcdn.com",
      @"adroll.com",
      @"smartadserver.com",
      @"bidswitch.net",
      @"serving-sys.com",
      @"exponential.com",
      @"sovrn.com",
      @"contextweb.com",
      @"triplelift.com",
      @"3lift.com",
      @"yieldmo.com",
      @"cootlogix.com",
      @"indexww.com",
      @"gumgum.com",
      @"sharethrough.com",
      @"applovin.com",
      @"unityads.unity3d.com",
      @"ironsrc.com",
      @"revcontent.com",
      @"zergnet.com",
      @"infolinks.com",
      @"bidvertiser.com",
      @"adkernel.com",
      @"sonobi.com",
      @"districtm.io",
      @"yieldlab.net",
      @"smaato.net",
      @"richaudience.com"
    ]];
  });

  NSString* norm = [host lowercaseString];
  if ([s_adDomains containsObject:norm]) return true;
  for (NSString* d in s_adDomains) {
    if ([norm hasSuffix:[@"." stringByAppendingString:d]]) {
      return true;
    }
  }
  return false;
}

} // namespace slate

