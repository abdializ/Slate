# Slate 0.4.23

- **Upgrade Twitch Ad Blocker to full vaft v37 engine (Normal & Incognito):**
  - Supports Twitch's `/api/v2/channel/hls/` usher endpoints, `ForceAccessTokenPlayerType = 'popout'` GQL rewriting, `embed`/`popout`/`autoplay` backup stream swapping, and blank-MP4 stitched ad segment stripping (`AdSegmentCache`).
  - Wraps Twitch's `*.twitch.tv` IVS WASM worker cleanly via WebKit-safe blob-revocation protection and skips module workers.
  - Includes automatic player buffering recovery and display-ad CSS hiding.
