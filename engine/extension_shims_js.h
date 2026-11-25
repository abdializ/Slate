// File purpose: Chrome WebExtension API compatibility shims for macOS WebKit
// (chrome.offscreen, chrome.sidePanel, chrome.identity.launchWebAuthFlow,
// chrome.notifications, chrome.runtime.getPlatformInfo, and safe optional API stubs).

#pragma once

namespace slate {

inline constexpr char kExtensionShimsJs[] = R"SLATE_EXT_SHIM((function() {
  'use strict';
  const proto = (typeof location !== 'undefined' && location.protocol) ? location.protocol.toLowerCase() : '';
  if (proto !== 'webkit-extension:' && proto !== 'safari-web-extension:' && proto !== 'chrome-extension:') {
    return;
  }
  if (window.__slateExtShimsInstalled) return;
  window.__slateExtShimsInstalled = true;

  const root = (typeof globalThis !== 'undefined') ? globalThis : window;
  const api = root.chrome || root.browser;
  if (!api) return;
  if (!root.chrome) root.chrome = api;
  if (!root.browser) root.browser = api;

  let nextReqId = 1;
  const pending = new Map();

  window.__slateExtShimReply = function(payload) {
    if (!payload || !payload.reqId) return;
    const entry = pending.get(payload.reqId);
    if (!entry) return;
    pending.delete(payload.reqId);
    if (payload.error) entry.reject(new Error(payload.error));
    else entry.resolve(payload.result);
  };

  function bridgeCall(op, params, callback) {
    const reqId = 'r' + (nextReqId++) + '_' + Date.now();
    const p = new Promise(function(resolve, reject) {
      pending.set(reqId, { resolve, reject });
      try {
        window.webkit.messageHandlers.slateExtShim.postMessage({
          reqId: reqId,
          op: op,
          extOrigin: location.origin,
          params: params || {}
        });
      } catch (e) {
        pending.delete(reqId);
        reject(e);
      }
    });
    if (typeof callback === 'function') {
      p.then(function(res) { callback(res); }, function() { callback(undefined); });
      return;
    }
    return p;
  }

  // 1. chrome.runtime.getPlatformInfo fallback
  if (api.runtime && typeof api.runtime.getPlatformInfo !== 'function') {
    api.runtime.getPlatformInfo = function(cb) {
      const info = { os: 'mac', arch: 'arm64', nacl_arch: 'arm' };
      if (typeof cb === 'function') { cb(info); return; }
      return Promise.resolve(info);
    };
  }

  // 2. chrome.offscreen shim (backed by hidden WKWebView in SlateExtensionsManager)
  if (!api.offscreen) {
    api.offscreen = {
      Reason: {
        AUDIO_PLAYBACK: 'AUDIO_PLAYBACK',
        BLOBS: 'BLOBS',
        CLIPBOARD: 'CLIPBOARD',
        DOM_PARSER: 'DOM_PARSER',
        DOM_SCRAPING: 'DOM_SCRAPING',
        IFRAME_SCRIPTING: 'IFRAME_SCRIPTING',
        LOCAL_STORAGE: 'LOCAL_STORAGE',
        MATCH_MEDIA: 'MATCH_MEDIA',
        TESTING: 'TESTING',
        USER_MEDIA: 'USER_MEDIA',
        WEB_RTC: 'WEB_RTC',
        WORKERS: 'WORKERS'
      },
      createDocument: function(opts, cb) {
        return bridgeCall('offscreen.create', opts || {}, cb);
      },
      closeDocument: function(cb) {
        return bridgeCall('offscreen.close', {}, cb);
      },
      hasDocument: function(cb) {
        return bridgeCall('offscreen.has', {}, cb);
      }
    };
  }

  // 3. chrome.sidePanel shim (backed by native SlateExtensionSidePanel)
  if (!api.sidePanel) {
    let panelOptions = { enabled: true, path: '' };
    let panelBehavior = { openPanelOnActionClick: false };
    api.sidePanel = {
      open: function(opts, cb) {
        const merged = Object.assign({}, panelOptions, opts || {});
        return bridgeCall('sidePanel.open', merged, cb);
      },
      setOptions: function(opts, cb) {
        panelOptions = Object.assign({}, panelOptions, opts || {});
        return bridgeCall('sidePanel.setOptions', panelOptions, cb);
      },
      getOptions: function(opts, cb) {
        const res = Object.assign({}, panelOptions);
        if (typeof cb === 'function') { cb(res); return; }
        return Promise.resolve(res);
      },
      setPanelBehavior: function(behavior, cb) {
        panelBehavior = Object.assign({}, panelBehavior, behavior || {});
        if (typeof cb === 'function') { cb(); return; }
        return Promise.resolve();
      },
      getPanelBehavior: function(cb) {
        const res = Object.assign({}, panelBehavior);
        if (typeof cb === 'function') { cb(res); return; }
        return Promise.resolve(res);
      }
    };
  }

  // 4. chrome.identity.launchWebAuthFlow shim (OAuth sheet/popup in Slate)
  if (!api.identity) {
    api.identity = {
      getRedirectURL: function(path) {
        const host = (location.host || 'slate').replace(/[^a-z0-9]/gi, '').toLowerCase();
        const suffix = path ? ('/' + String(path).replace(/^\/+/, '')) : '/';
        return 'https://' + host + '.chromiumapp.org' + suffix;
      },
      launchWebAuthFlow: function(details, cb) {
        return bridgeCall('identity.launchWebAuthFlow', details || {}, cb);
      },
      getAuthToken: function(details, cb) {
        const err = new Error('chrome.identity.getAuthToken requires Google Sign-In; use launchWebAuthFlow.');
        if (typeof cb === 'function') { cb(undefined); return; }
        return Promise.reject(err);
      }
    };
  }

  // 5. chrome.notifications shim
  if (!api.notifications) {
    let notifSeq = 1;
    api.notifications = {
      create: function(id, options, cb) {
        if (typeof id === 'object') { cb = options; options = id; id = 'slate_notif_' + (notifSeq++); }
        if (!id) id = 'slate_notif_' + (notifSeq++);
        return bridgeCall('notifications.create', { id: String(id), options: options || {} }, cb);
      },
      clear: function(id, cb) {
        if (typeof cb === 'function') { cb(true); return; }
        return Promise.resolve(true);
      },
      getAll: function(cb) {
        if (typeof cb === 'function') { cb({}); return; }
        return Promise.resolve({});
      },
      onClicked: { addListener: function() {}, removeListener: function() {}, hasListener: function() { return false; } },
      onClosed: { addListener: function() {}, removeListener: function() {}, hasListener: function() { return false; } }
    };
  }

  // 6. Safe stubs for optional Chrome-only APIs so extensions never crash on startup
  if (!api.idle) {
    api.idle = {
      queryState: function(interval, cb) {
        if (typeof cb === 'function') { cb('active'); return; }
        return Promise.resolve('active');
      },
      setDetectionInterval: function() {},
      onStateChanged: { addListener: function() {}, removeListener: function() {}, hasListener: function() { return false; } }
    };
  }
  if (!api.management) {
    api.management = {
      getSelf: function(cb) {
        const selfInfo = {
          id: location.host || '',
          name: (api.runtime && api.runtime.getManifest && api.runtime.getManifest().name) || 'Extension',
          version: (api.runtime && api.runtime.getManifest && api.runtime.getManifest().version) || '1.0',
          enabled: true,
          installType: 'normal',
          type: 'extension'
        };
        if (typeof cb === 'function') { cb(selfInfo); return; }
        return Promise.resolve(selfInfo);
      }
    };
  }
  // 7. Notify host when declarativeNetRequest rulesets finish compiling so Slate
  // immediately hands empty WebKit compilation pages back to macOS.
  if (api.declarativeNetRequest) {
    const dnr = api.declarativeNetRequest;
    const notifyBuilt = function() {
      try { bridgeCall('memory.rulesBuilt', {}).catch(function() {}); } catch (e) {}
    };
    ['updateEnabledRulesets', 'updateDynamicRules', 'updateSessionRules'].forEach(function(fn) {
      if (typeof dnr[fn] !== 'function') return;
      const orig = dnr[fn].bind(dnr);
      try {
        dnr[fn] = function() {
          const args = Array.prototype.slice.call(arguments);
          const last = args.length ? args[args.length - 1] : null;
          if (typeof last === 'function') {
            args[args.length - 1] = function() {
              notifyBuilt();
              return last.apply(this, arguments);
            };
            return orig.apply(dnr, args);
          }
          const res = orig.apply(dnr, args);
          if (res && typeof res.then === 'function') {
            res.then(notifyBuilt, function() {});
          }
          return res;
        };
      } catch (e) {}
    });
  }
})();)SLATE_EXT_SHIM";

} // namespace slate
