# Slate 0.5.9

## Fixes
- Fixed invisible white-on-white tab titles inside the active horizontal split tab container by matching all partner pills' text ink to the active bar surface and highlighting the focused split tab with an appearance-adapted Settings accent inner pill.
- Replaced the flared active split tab stroke with a clean floating rounded pill outline so the Settings accent outer line wraps cleanly on all four sides without cutting across the toolbar seam.
- Fixed drag-to-split in vertical sidebar tab mode (preventing child `WKWebView`s from cancelling the drag preview or swallowing drop completion, and arming sidebar edge drops immediately).
- Grouped split tabs in the vertical sidebar into stacked vertical cards with fused top/middle/bottom corners and your appearance-adapted Settings accent outer border.
