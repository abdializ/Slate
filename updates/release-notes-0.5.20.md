# Slate 0.5.20

## Split View Video Playback Fix
- Removed the private WebKit tile-eviction and occlusion SPIs (`_setAggressiveTileRetentionEnabled:NO`, `_setWindowOcclusionDetectionEnabled:YES`, `_setInvisibleMediaAutoplayNotPermitted:YES`) added in v0.5.17 that disrupted GPU compositor tile retention and caused hardware-decoded video glitching in Split View panes, while preserving all v0.5.18–v0.5.19 memory wins (~61–66 MB main-process footprint).
- Moved the Split View outer focus ring (`splitFocusRing`) strictly **behind** the opaque split panes (peeking 2 pt into the gutter) so no sibling overlay layer ever sits above a `WKWebView` hardware video surface.
- Lowered the primary-player size heuristic in the site memory optimizer (`280×160`) so narrow Split View video players are never misclassified as feed previews.
