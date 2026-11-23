// File purpose: Contains site compatibility overrides used by the WebKit shields adapter.

#pragma once

namespace slate {
// Slate note: The bypass suffix list excludes sensitive sign-in, verification, and streaming hosts
// from overrides. Avoid mutating Function.prototype.toString, navigator own-properties, or live
// canvas pixels, as those trip anti-bot checks (e.g. Cloudflare Turnstile) and break sites.
inline constexpr char kStealthJs[] = R"JS((function() {
  var guardSym = Symbol.for('__slate_stealth_active__');
  if (window[guardSym]) return;
  try {
    var host = (window.location && window.location.hostname) ? window.location.hostname.toLowerCase() : '';
    if (!host && document.referrer) {
      try { host = (new URL(document.referrer)).hostname.toLowerCase(); } catch(e) {}
    }
    var bypassSuffixes = [
      'cloudflare.com', 'challenges.cloudflare.com',
      'hcaptcha.com', 'recaptcha.net', 'arkoselabs.com', 'funcaptcha.com',
      'datadome.co', 'captcha-delivery.com', 'perimeterx.net',
      'google.com', 'accounts.google.com', 'gstatic.com', 'googleusercontent.com', 'googleapis.com',
      'apple.com', 'icloud.com', 'appleid.apple.com',
      'microsoft.com', 'live.com', 'login.microsoftonline.com', 'office.com',
      'max.com', 'hbomax.com', 'hbo.com', 'discomax.com', 'h264.io', 'warnermediacdn.com', 'warnermedia.com', 'wbd.com',
      'netflix.com', 'nflxvideo.net', 'nflximg.net', 'nflxext.com',
      'disneyplus.com', 'bamgrid.com', 'disney-plus.net',
      'hulu.com', 'hulustream.com',
      'peacocktv.com', 'paramountplus.com',
      'primevideo.com', 'amazon.com', 'amazonvideo.com', 'aiv-cdn.net',
      'spotify.com', 'crunchyroll.com', 'tubitv.com', 'pluto.tv',
      'fubo.tv', 'sling.com', 'starz.com', 'mgmplus.com',
      'directv.com', 'sho.com', 'showtime.com',
      'youtube.com', 'twitch.tv', 'kick.com'
    ];
    for (var i = 0; i < bypassSuffixes.length; i++) {
      var s = bypassSuffixes[i];
      if (host === s || host.endsWith('.' + s)) {
        return;
      }
    }
  } catch(e) {}
  try {
    window[guardSym] = true;
  } catch (e) {}

  // Battery API neutralization (safe no-op on WebKit, which does not expose getBattery)
  try {
    if (navigator.getBattery) {
      var mockBattery = {
        charging: true,
        chargingTime: 0,
        dischargingTime: Infinity,
        level: 1.0,
        addEventListener: function() {},
        removeEventListener: function() {},
        dispatchEvent: function() { return false; },
        onchargingchange: null,
        onchargingtimechange: null,
        ondischargingtimechange: null,
        onlevelchange: null
      };
      navigator.getBattery = function() {
        return Promise.resolve(mockBattery);
      };
    }
  } catch (e) {}

})();
)JS";
} // namespace slate
