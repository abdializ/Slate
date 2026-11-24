# Slate 0.5.10

## Fixes
- Fixed sidebar drag-to-split failing on release because `splitSourceTab` was cleared before `finishSplitDragAtScreenPoint:` validated the drop.
- Separated **Split View** from **New Window Tear-Off** across both sidebar and horizontal tab modes:
  - Dragging onto the left/right edge of a page inside the window creates/adds a split pane.
  - Dropping in the middle of a page inside the window cleanly cancels instead of tearing off.
  - Dragging outside the browser window frame tears the tab off into its own window.
