# Slate 0.5.13

## Fixes
- Fixed all hardware-accelerated videos glitching in Split View: removed `cornerRadius`, `borderWidth`, and behind-pane shadow layers from `WKWebView` split containers so macOS WindowServer no longer forces offscreen rounded-mask compositing on remote video IOSurfaces.
- Positioned the appearance-adapted Settings accent outer focus border (`splitFocusRing`) cleanly outside the focused pane frame (`-2pt` outset in the gutter) and guarded frame updates so `syncPageGeometry` never invalidates video layers during playback.
