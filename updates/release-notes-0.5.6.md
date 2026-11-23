# Slate 0.5.6

- **Stronger Native Ad Blocking in Incognito & Normal Tabs:**
  - Added a document-start YouTube `ytInitialPlayerResponse` ad stripper so YouTube pre-roll ads are removed before the player initializes (fixing ads slipping through in Incognito when extensions are off).
  - Added native WebKit `css-display-none` cosmetic ad rules for Google Search sponsored ads (`#tads`, `[data-text-ad]`), Reddit promoted posts (`shreddit-ad-post`), and additional YouTube ad slots (`#player-ads`, `ytd-promoted-sparkles-web-renderer`).
  - Fixed the toolbar Shields icon in Incognito to accurately reflect active Incognito protection even when normal-tab ad blocking is turned off.
