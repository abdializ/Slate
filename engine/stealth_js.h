#pragma once

namespace slate {
inline constexpr char kStealthJs[] = R"JS((function() {
  if (window.__slate_stealth_active__) return;
  try {
    var host = (window.location && window.location.hostname) ? window.location.hostname.toLowerCase() : '';
    if (!host && document.referrer) {
      try { host = (new URL(document.referrer)).hostname.toLowerCase(); } catch(e) {}
    }
    var bypassSuffixes = [
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
    Object.defineProperty(window, '__slate_stealth_active__', {
      value: true,
      configurable: false,
      enumerable: false,
      writable: false
    });
  } catch (e) {
    window.__slate_stealth_active__ = true;
  }

  // Preserve native function toString() appearance
  const nativeToString = Function.prototype.toString;
  const hookedFns = new Set();
  function protectNative(fn) {
    hookedFns.add(fn);
    return fn;
  }
  try {
    Function.prototype.toString = function() {
      if (hookedFns.has(this)) {
        return 'function ' + (this.name || '') + '() { [native code] }';
      }
      return nativeToString.call(this);
    };
    hookedFns.add(Function.prototype.toString);
  } catch (e) {}

  // 1. Canvas Fingerprinting Protection
  // Introduce deterministic 1-bit micro-entropy on image data exports to scramble tracking hashes
  // while preserving 100% visual fidelity for games and graphics.
  try {
    const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;
    CanvasRenderingContext2D.prototype.getImageData = protectNative(function(sx, sy, sw, sh) {
      const imageData = origGetImageData.apply(this, arguments);
      const data = imageData.data;
      const len = data.length;
      if (len >= 4) {
        // Deterministic micro-perturbation on a few pseudo-random pixel positions
        const step = Math.max(4, Math.floor(len / 16));
        for (let i = 0; i < len; i += step) {
          // Adjust red or blue channel by at most 1 LSB
          data[i] = (data[i] ^ 1);
        }
      }
      return imageData;
    });

    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = protectNative(function() {
      try {
        if (!this.getContext('webgl') && !this.getContext('webgl2')) {
          const ctx = this.getContext('2d');
          if (ctx && this.width > 0 && this.height > 0) {
            const img = ctx.getImageData(0, 0, Math.min(2, this.width), Math.min(2, this.height));
            if (img.data.length >= 4) {
              img.data[0] = (img.data[0] ^ 1);
              ctx.putImageData(img, 0, 0);
            }
          }
        }
      } catch (err) {}
      return origToDataURL.apply(this, arguments);
    });

    const origToBlob = HTMLCanvasElement.prototype.toBlob;
    if (origToBlob) {
      HTMLCanvasElement.prototype.toBlob = protectNative(function(callback, type, quality) {
        try {
          if (!this.getContext('webgl') && !this.getContext('webgl2')) {
            const ctx = this.getContext('2d');
            if (ctx && this.width > 0 && this.height > 0) {
              const img = ctx.getImageData(0, 0, Math.min(2, this.width), Math.min(2, this.height));
              if (img.data.length >= 4) {
                img.data[0] = (img.data[0] ^ 1);
                ctx.putImageData(img, 0, 0);
              }
            }
          }
        } catch (err) {}
        return origToBlob.apply(this, arguments);
      });
    }
  } catch (e) {}

  // 2. AudioContext Fingerprinting Protection
  // Inject subtle noise into frequency analysis without corrupting live PCM audio buffers
  try {
    if (window.AnalyserNode) {
      const origGetFloatFreq = AnalyserNode.prototype.getFloatFrequencyData;
      AnalyserNode.prototype.getFloatFrequencyData = protectNative(function(array) {
        origGetFloatFreq.call(this, array);
        for (let i = 0; i < array.length; i += 8) {
          array[i] += 0.00001;
        }
      });
    }
  } catch (e) {}

  // 3. Hardware & Concurrency Spoofing
  try {
    Object.defineProperty(navigator, 'hardwareConcurrency', {
      get: protectNative(function() { return 8; }),
      configurable: true,
      enumerable: true
    });
  } catch (e) {}

  try {
    Object.defineProperty(navigator, 'deviceMemory', {
      get: protectNative(function() { return 8; }),
      configurable: true,
      enumerable: true
    });
  } catch (e) {}

  try {
    Object.defineProperty(navigator, 'maxTouchPoints', {
      get: protectNative(function() { return 0; }),
      configurable: true,
      enumerable: true
    });
  } catch (e) {}

  // 4. Battery API Neutralization
  try {
    if (navigator.getBattery) {
      const mockBattery = {
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
      navigator.getBattery = protectNative(function() {
        return Promise.resolve(mockBattery);
      });
    }
  } catch (e) {}

})();
)JS";
} // namespace slate
