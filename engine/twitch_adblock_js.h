// File purpose: Native Twitch HLS Web Worker & fetch stitched-ad blocker (vaft-style backup
// stream swapper + ad-cue stripper + display-ad hider) for both Normal and Incognito tabs.

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

  // 2. Worker-side HLS playlist interceptor (injected before Twitch's IVS WASM worker runs)
  const workerHookSource = `
  (function() {
    if (self.__slateTwitchWorkerShield) return;
    self.__slateTwitchWorkerShield = true;

    const CLIENT_ID = 'kimne78kx3ncx6brgo4mv6wki5h1ko';
    const AD_SIGNIFIER = 'stitched';
    const BACKUP_PLAYER_TYPES = ['embed', 'popout', 'autoplay', 'frontpage'];
    const GQL_URL = 'https://gql.twitch.tv/gql';
    const USHER_BASE = 'https://usher.ttvnw.net/api/channel/hls/';

    const realFetch = self.fetch.bind(self);
    let clientId = CLIENT_ID;
    let deviceId = null;
    let authHeader = null;

    // Channel state map: channelName -> { masterUrl, backupUrl, backupPlayerIdx, lastBackupAt, isStripping, selectedRes }
    const channels = new Map();
    // Variant URL -> { channel, resolution }
    const variantToChannel = new Map();

    self.addEventListener('message', function(ev) {
      const d = ev && ev.data;
      if (!d || d.__slateTwitchMeta !== true) return;
      if (d.clientId) clientId = d.clientId;
      if (d.deviceId) deviceId = d.deviceId;
      if (d.authHeader) authHeader = d.authHeader;
    });

    function hasStitchedAds(text) {
      if (!text) return false;
      return text.includes('stitched-ad') ||
             text.includes('twitch-stitched-ad') ||
             text.includes('amazon-adsystem') ||
             text.includes('CLASS="twitch-ad') ||
             (text.includes('#EXT-X-DATERANGE') && text.includes(AD_SIGNIFIER));
    }

    function stripAdCues(text) {
      if (!text) return text;
      const lines = text.split('\\n');
      const out = [];
      let skipNextUri = false;
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.startsWith('#EXT-X-DATERANGE') &&
            (line.includes('stitched-ad') || line.includes('twitch-ad') || line.includes('amazon-adsystem'))) {
          continue;
        }
        if (line.startsWith('#EXT-X-SCTE35-OUT') || line.startsWith('#EXT-X-SCTE35-IN')) {
          continue;
        }
        if (line.startsWith('#EXTINF') && line.includes('Amazon')) {
          skipNextUri = true;
          continue;
        }
        if (skipNextUri && line && !line.startsWith('#')) {
          skipNextUri = false;
          continue;
        }
        out.push(line);
      }
      return out.join('\\n');
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
      const headers = {
        'Client-ID': clientId || CLIENT_ID,
        'Content-Type': 'application/json'
      };
      if (deviceId) headers['X-Device-Id'] = deviceId;
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
      const resp = await realFetch(GQL_URL, { method: 'POST', headers, body });
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

      // Reuse cached clean backup variant URL if fresh (< 20s)
      if (state.backupUrl && (Date.now() - state.lastBackupAt) < 20000) {
        try {
          const r = await realFetch(state.backupUrl);
          if (r.ok) {
            const txt = await r.text();
            if (txt && txt.includes('#EXTM3U') && !hasStitchedAds(txt)) {
              return stripAdCues(txt);
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
            return stripAdCues(mediaText);
          }
        } catch (e) {}
      }
      return null;
    }

    self.fetch = async function(input, init) {
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      if (!url) return realFetch(input, init);

      // Master playlist from usher.ttvnw.net
      if (url.includes('usher.ttvnw.net/api/channel/hls/') && url.includes('.m3u8')) {
        const resp = await realFetch(input, init);
        const channel = parseChannelFromUsher(url);
        if (channel && resp.ok) {
          const text = await resp.text();
          indexMasterPlaylist(channel, text);
          return new Response(text, { status: resp.status, statusText: resp.statusText, headers: resp.headers });
        }
        return resp;
      }

      // Media playlist from *.hls.ttvnw.net
      if (url.includes('.m3u8') && (url.includes('ttvnw.net') || variantToChannel.has(url))) {
        const resp = await realFetch(input, init);
        if (!resp.ok) return resp;
        const text = await resp.text();
        if (hasStitchedAds(text)) {
          const meta = variantToChannel.get(url);
          if (meta && meta.channel) {
            const clean = await fetchCleanBackupPlaylist(meta.channel, meta.resolution);
            if (clean) {
              return new Response(clean, { status: 200, statusText: 'OK', headers: resp.headers });
            }
          }
          // Fallback: strip ad cue metadata and Amazon ad segments
          return new Response(stripAdCues(text), { status: resp.status, statusText: resp.statusText, headers: resp.headers });
        }
        return new Response(text, { status: resp.status, statusText: resp.statusText, headers: resp.headers });
      }

      return realFetch(input, init);
    };
  })();
  `;

  // 3. Wrap window.Worker so Twitch's IVS HLS worker gets our fetch hook automatically
  const activeWorkers = new Set();
  let lastMeta = { __slateTwitchMeta: true, clientId: null, deviceId: null, authHeader: null };

  function broadcastMeta() {
    activeWorkers.forEach(w => {
      try { w.postMessage(lastMeta); } catch (e) {}
    });
  }

  try {
    const OrigWorker = window.Worker;
    if (typeof OrigWorker === 'function') {
      const WrappedWorker = function(scriptURL, options) {
        const urlStr = typeof scriptURL === 'string' ? scriptURL : String(scriptURL || '');
        const shouldWrap = urlStr.startsWith('blob:') ||
                           urlStr.includes('twitch') ||
                           urlStr.includes('ttvnw') ||
                           urlStr.includes('amazon-ivs') ||
                           urlStr.includes('wasmworker');
        if (!shouldWrap) {
          return new OrigWorker(scriptURL, options);
        }
        try {
          const bootstrap = workerHookSource + '\nimportScripts(' + JSON.stringify(urlStr) + ');\n';
          const blob = new Blob([bootstrap], { type: 'application/javascript' });
          const wrappedUrl = URL.createObjectURL(blob);
          const worker = new OrigWorker(wrappedUrl, options);
          activeWorkers.add(worker);
          try { worker.postMessage(lastMeta); } catch (e) {}
          const origTerminate = worker.terminate.bind(worker);
          worker.terminate = function() {
            activeWorkers.delete(worker);
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

  // 4. Intercept main-thread fetch to capture Twitch Client-ID/Device-ID & neutralize ad event beacons
  try {
    const origFetch = window.fetch.bind(window);
    window.fetch = function(input, init) {
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      if (url && url.includes('gql.twitch.tv/gql')) {
        try {
          const h = init && init.headers;
          let changed = false;
          if (h) {
            const getH = (k) => (h instanceof Headers) ? h.get(k) : (h[k] || h[k.toLowerCase()]);
            const cid = getH('Client-ID') || getH('Client-Id');
            const did = getH('X-Device-Id');
            const auth = getH('Authorization');
            if (cid && cid !== lastMeta.clientId) { lastMeta.clientId = cid; changed = true; }
            if (did && did !== lastMeta.deviceId) { lastMeta.deviceId = did; changed = true; }
            if (auth && auth !== lastMeta.authHeader) { lastMeta.authHeader = auth; changed = true; }
            if (changed) broadcastMeta();
          }
          // Neutralize client-side ad telemetry beacons without breaking player state
          if (init && typeof init.body === 'string' &&
              (init.body.includes('ClientSideAdEventHandling_RecordAdEvent') ||
               init.body.includes('videoAdRequestDecline'))) {
            return Promise.resolve(new Response(JSON.stringify({ data: {} }), {
              status: 200,
              headers: { 'Content-Type': 'application/json' }
            }));
          }
        } catch (e) {}
      }
      return origFetch(input, init);
    };
  } catch (e) {}
})();)JS";

} // namespace slate
