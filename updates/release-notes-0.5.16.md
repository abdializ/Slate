# Slate 0.5.16

## Improvements
- **Real Logos for Unloaded Tabs (Zero RAM):** Favicons are now cached per host on disk (`favicons/<host>.png`) and fetched via lightweight icon-only requests without creating any `WKWebView`, so unloaded/sleeping tabs show each site’s real logo instead of generic letter circles while using zero tab RAM.
- **Dimmed Unloaded State:** Unloaded tabs dim their favicon (and title) cleanly in both the sidebar and horizontal tab bar to indicate sleeping/zero-RAM status.
