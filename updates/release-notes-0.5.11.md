# Slate 0.5.11

## Fixes
- Replaced `NSTableView`'s CoreDrag session for sidebar tabs with a direct event tracking loop (matching horizontal tab dragging and lovesea), completely fixing sidebar drag-to-split over `WKWebView` pages.
- Dragging any tab from the vertical sidebar now gives immediate 60fps edge bands and live multi-pane drop preview (2–4 panes), live sidebar reordering when dragged within the sidebar, clean cancel when dropped in the middle of a page, and window tear-off only when dragged outside the browser window.
