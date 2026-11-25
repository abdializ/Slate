# Slate 0.5.21

## Major Native Ad Blocking Upgrade (SlateShields V17)
- **Fixed EasyList & EasyPrivacy truncation:** Raised `kMaxRulesPerList` from 20,000 to 55,000 (well within macOS WebKit's 150,000-rule `WKContentRuleList` ceiling), recovering **~40,000 previously truncated rules** (every EasyList/EasyPrivacy domain alphabetically from `I` through `Z`, including `monetag.com`, `popads.net`, `popcash.net`, and `propellerads.com`).
- **Native popunder & ad-popup blocking:** Added 45 major popunder, streaming, and redirect ad networks to `SlateShields` and wired `WKUIDelegate` popup creation (`createWebViewWithConfiguration:`) to cancel ad-network popups & promo redirects when Shields is active.
- **First-party ad blocking for `novahd.cc`:** Added native network blocks for `/assets/p/*` and `/r/*`, cosmetic hiding for `[class*='promo-']` / `.home-promo-hero` / `a[href^='/r/']`, and a document-start `/api/config` JSON pruner (matching uBlock Origin's `json-prune`) that cleanly strips self-hosted Stake banners, pre-roll/mid-roll sponsor videos, and popunders without breaking playback.
- **Seamless navigation rule attachment:** Cached per-controller rule-list attachment state in `UpdateControllerForURL` so navigating between shielded pages no longer strips and re-adds the compiled rule list on every click.
