// File purpose: Native Twitch HLS Web Worker stitched-ad blocker (vaft-style backup stream
// swapper + display-ad hider) for both Normal and Incognito tabs.

#pragma once

namespace slate {

inline constexpr char kTwitchAdBlockJs[] = R"JS((function() {
  'use strict';
  const host = (window.location && window.location.hostname || '').toLowerCase();
  if (host !== 'twitch.tv' && !host.endsWith('.twitch.tv')) return;
  if (window.__slateTwitchShield) return;
  window.__slateTwitchShield = true;

  // 1. Hide Twitch display/banner/companion ads immediately at document start
  try {
    const style = document.createElement('style');
    style.id = '__slate_twitch_ad_css__';
    style.textContent = `
      .stream-display-ad__wrapper,
      .stream-display-ad__container,
      [data-a-target="video-ad-label"],
      [data-a-target="video-ad-countdown"],
      [data-test-selector="ad-banner-default-text"],
      div[class*="StreamDisplayAd"],
      div[class*="DisplayAd__"],
      div[class*="ad-banner"],
      iframe[src*="amazon-adsystem"],
      iframe[src*="doubleclick.net"] {
        display: none !important;
        visibility: hidden !important;
        height: 0 !important;
        max-height: 0 !important;
        opacity: 0 !important;
        pointer-events: none !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  } catch (e) {}

  // 2. Worker-side HLS playlist interceptor (injected ONLY into Twitch's IVS WASM worker)
  const workerHookSource = `
  (function() {
    if (self.__slateTwitchWorkerShield) return;
    self.__slateTwitchWorkerShield = true;

    const CLIENT_ID = 'kimne78kx3ncx6brgo4mv6wki5h1ko';
    const AD_SIGNIFIER = 'stitched';
    const BACKUP_PLAYER_TYPES = ['embed', 'popout', 'autoplay'];
    const GQL_URL = 'https://gql.twitch.tv/gql';
    const USHER_BASE = 'https://usher.ttvnw.net/api/channel/hls/';

    const realFetch = self.fetch.bind(self);
    const channels = new Map();
    const variantToChannel = new Map();

    function makeResponseWithUrl(body, origResp, fallbackUrl) {
      const modified = new Response(body, {
        status: origResp.status || 200,
        statusText: origResp.statusText || 'OK',
        headers: origResp.headers
      });
      try {
        Object.defineProperty(modified, 'url', { value: origResp.url || fallbackUrl || '' });
      } catch (e) {}
      return modified;
    }

    function hasStitchedAds(text) {
      if (!text) return false;
      return text.includes('stitched-ad') ||
             text.includes('twitch-stitched-ad') ||
             text.includes('amazon-adsystem') ||
             (text.includes('#EXT-X-DATERANGE') && text.includes(AD_SIGNIFIER));
    }

    function parseChannelFromUsher(url) {
      const m = url.match(/\\/api\\/channel\\/hls\\/([^/.?]+)\\.m3u8/i);
      return m ? m[1].toLowerCase() : null;
    }

    function indexMasterPlaylist(channel, text) {
      const lines = text.split('\\n');
      let lastRes = '';
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          const rm = line.match(/RESOLUTION=(\\d+x\\d+)/i);
          lastRes = rm ? rm[1] : '';
        } else if (line.startsWith('http')) {
          variantToChannel.set(line, { channel, resolution: lastRes });
        }
      }
    }

    function pickBestVariant(masterText, preferredRes) {
      const lines = masterText.split('\\n');
      const variants = [];
      let res = '';
      let bw = 0;
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          const rm = line.match(/RESOLUTION=(\\d+x\\d+)/i);
          const bm = line.match(/BANDWIDTH=(\\d+)/i);
          res = rm ? rm[1] : '';
          bw = bm ? parseInt(bm[1], 10) : 0;
        } else if (line.startsWith('http')) {
          variants.push({ url: line, res, bw });
        }
      }
      if (!variants.length) return null;
      if (preferredRes) {
        const exact = variants.find(v => v.res === preferredRes);
        if (exact) return exact.url;
      }
      variants.sort((a, b) => b.bw - a.bw);
      return variants[0].url;
    }

    async function fetchBackupAccessToken(channel, playerType) {
      const body = JSON.stringify({
        operationName: 'PlaybackAccessToken',
        extensions: {
          persistedQuery: {
            version: 1,
            sha256Hash: '0828119ded1c13477966434e15800ff57ddacf13ba1911c129dc2200705b0712'
          }
        },
        variables: {
          isLive: true,
          login: channel,
          isVod: false,
          vodID: '',
          playerType: playerType
        }
      });
      const resp = await realFetch(GQL_URL, {
        method: 'POST',
        headers: {
          'Client-ID': CLIENT_ID,
          'Content-Type': 'application/json'
        },
        body
      });
      if (!resp.ok) return null;
      const json = await resp.json();
      const tokenObj = json && json.data && json.data.streamPlaybackAccessToken;
      if (!tokenObj || !tokenObj.value || !tokenObj.signature) return null;
      return tokenObj;
    }

    async function fetchCleanBackupPlaylist(channel, preferredRes) {
      let state = channels.get(channel);
      if (!state) {
        state = { backupUrl: null, backupPlayerIdx: 0, lastBackupAt: 0 };
        channels.set(channel, state);
      }

      if (state.backupUrl && (Date.now() - state.lastBackupAt) < 20000) {
        try {
          const r = await realFetch(state.backupUrl);
          if (r.ok) {
            const txt = await r.text();
            if (txt && txt.includes('#EXTM3U') && !hasStitchedAds(txt)) {
              return { text: txt, url: r.url || state.backupUrl };
            }
          }
        } catch (e) {}
        state.backupUrl = null;
      }

      for (let attempt = 0; attempt < BACKUP_PLAYER_TYPES.length; attempt++) {
        const idx = (state.backupPlayerIdx + attempt) % BACKUP_PLAYER_TYPES.length;
        const playerType = BACKUP_PLAYER_TYPES[idx];
        try {
          const tok = await fetchBackupAccessToken(channel, playerType);
          if (!tok) continue;
          const p = Math.floor(Math.random() * 9999999);
          const usherUrl = USHER_BASE + encodeURIComponent(channel) + '.m3u8'
            + '?allow_source=true&fast_bread=true&allow_audio_only=true'
            + '&player_backend=mediaplayer&playlist_include_framerate=true&reassignments_supported=true'
            + '&p=' + p
            + '&sig=' + encodeURIComponent(tok.signature)
            + '&token=' + encodeURIComponent(tok.value);
          const masterResp = await realFetch(usherUrl);
          if (!masterResp.ok) continue;
          const masterText = await masterResp.text();
          const variantUrl = pickBestVariant(masterText, preferredRes);
          if (!variantUrl) continue;
          const mediaResp = await realFetch(variantUrl);
          if (!mediaResp.ok) continue;
          const mediaText = await mediaResp.text();
          if (mediaText && mediaText.includes('#EXTM3U') && !hasStitchedAds(mediaText)) {
            state.backupUrl = variantUrl;
            state.backupPlayerIdx = idx;
            state.lastBackupAt = Date.now();
            return { text: mediaText, url: mediaResp.url || variantUrl };
          }
        } catch (e) {}
      }
      return null;
    }

    self.fetch = async function(input, init) {
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      if (!url) return realFetch(input, init);

      // Master playlist from usher.ttvnw.net: inspect a clone, return original Response untouched
      if (url.includes('usher.ttvnw.net/api/channel/hls/') && url.includes('.m3u8')) {
        const resp = await realFetch(input, init);
        const channel = parseChannelFromUsher(url);
        if (channel && resp.ok) {
          try {
            const text = await resp.clone().text();
            indexMasterPlaylist(channel, text);
          } catch (e) {}
        }
        return resp;
      }

      // Media playlist from *.hls.ttvnw.net: inspect a clone, only replace if stitched ads are present
      if (url.includes('.m3u8') && (url.includes('ttvnw.net') || variantToChannel.has(url))) {
        const resp = await realFetch(input, init);
        if (!resp.ok) return resp;
        try {
          const text = await resp.clone().text();
          if (hasStitchedAds(text)) {
            const meta = variantToChannel.get(url);
            if (meta && meta.channel) {
              const clean = await fetchCleanBackupPlaylist(meta.channel, meta.resolution);
              if (clean && clean.text) {
                return makeResponseWithUrl(clean.text, resp, clean.url);
              }
            }
          }
        } catch (e) {}
        return resp;
      }

      return realFetch(input, init);
    };
  })();
  `;

  // 3. Identify ONLY Twitch's IVS player worker bootstrap blobs (avoid wrapping unrelated workers
  //    or doing nested importScripts('blob:...') which fails in WebKit)
  const ivsBlobSources = new WeakMap();
  const ivsBlobUrlToSource = new Map();
  const OrigBlob = window.Blob;
  try {
    if (typeof OrigBlob === 'function') {
      const TrackedBlob = function(parts, options) {
        const blob = new OrigBlob(parts, options);
        try {
          if (Array.isArray(parts) && parts.length > 0 && parts.length <= 4) {
            let joined = '';
            let allStrings = true;
            for (let i = 0; i < parts.length; i++) {
              if (typeof parts[i] !== 'string' || parts[i].length > 4096) {
                allStrings = false;
                break;
              }
              joined += parts[i];
            }
            if (allStrings && joined.length > 0 && joined.length <= 4096 &&
                (joined.includes('amazon-ivs') || joined.includes('wasmworker'))) {
              ivsBlobSources.set(blob, joined);
            }
          }
        } catch (e) {}
        return blob;
      };
      TrackedBlob.prototype = OrigBlob.prototype;
      Object.setPrototypeOf(TrackedBlob, OrigBlob);
      window.Blob = TrackedBlob;
    }

    const origCreateObjectURL = URL.createObjectURL.bind(URL);
    URL.createObjectURL = function(obj) {
      const url = origCreateObjectURL(obj);
      try {
        if (obj && ivsBlobSources.has(obj)) {
          ivsBlobUrlToSource.set(url, ivsBlobSources.get(obj));
        }
      } catch (e) {}
      return url;
    };
  } catch (e) {}

  // 4. Wrap ONLY the Twitch IVS player Worker with flat inline source (no postMessage pollution)
  try {
    const OrigWorker = window.Worker;
    if (typeof OrigWorker === 'function') {
      const WrappedWorker = function(scriptURL, options) {
        const urlStr = typeof scriptURL === 'string' ? scriptURL : String(scriptURL || '');
        const isModule = options && options.type === 'module';
        if (isModule) {
          return new OrigWorker(scriptURL, options);
        }

        let bootstrap = null;
        if (ivsBlobUrlToSource.has(urlStr)) {
          bootstrap = workerHookSource + '\n' + ivsBlobUrlToSource.get(urlStr) + '\n';
        } else if (urlStr.startsWith('http') &&
                   (urlStr.includes('amazon-ivs') || urlStr.includes('wasmworker'))) {
          bootstrap = workerHookSource + '\nimportScripts(' + JSON.stringify(urlStr) + ');\n';
        }

        if (!bootstrap) {
          return new OrigWorker(scriptURL, options);
        }

        try {
          const blob = new OrigBlob([bootstrap], { type: 'application/javascript' });
          const wrappedUrl = URL.createObjectURL(blob);
          const worker = new OrigWorker(wrappedUrl, options);
          const origTerminate = worker.terminate.bind(worker);
          worker.terminate = function() {
            try { URL.revokeObjectURL(wrappedUrl); } catch (e) {}
            return origTerminate();
          };
          return worker;
        } catch (e) {
          return new OrigWorker(scriptURL, options);
        }
      };
      WrappedWorker.prototype = OrigWorker.prototype;
      Object.setPrototypeOf(WrappedWorker, OrigWorker);
      window.Worker = WrappedWorker;
    }
  } catch (e) {}
})();)JS";

} // namespace slate
