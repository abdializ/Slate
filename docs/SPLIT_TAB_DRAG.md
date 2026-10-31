# Split-tab dragging

This update adapts the supplied `SplitDropZone` / `TabDrag` behavior to Slate's
existing native tab gestures. Preview views are passive (`hitTest` returns nil);
they do not capture the mouse or start a second drag session.

A split is offered only at a page edge: a band of 24% of its width, at least 120
points. The pointer must settle within six points over 90 ms. The active band
retains 20 points of tolerance, and the preview disappears when the pointer leaves
it. A stationary drag is rechecked by the existing gesture's tracking loop or
native drag timer. Entering the middle of a page offers no split.

An armed preview highlights the half the dragged page will occupy, shows its
name and icon, and provides alignment haptic feedback. Releasing only commits a
preview that was already visible and still matches the target and side. A release
cannot arm a split by itself.

The tab strip reorders tabs. Dropping one half of a split onto an unrelated tab
or an empty part of the strip separates that half; dropping onto its own pair
preserves the pair. Horizontal pills and vertical rows already identify the exact
half under the pointer, so the active pane does not substitute for the half being
dragged. Existing live WebKit views are reused through these operations.

Escape cancels a drag. The native sidebar's temporary Escape monitor is removed
on cancellation, release, shutdown, or a space change. It passes Escape through
when the mouse is no longer pressed, preventing an abandoned drag from consuming
a later full-screen video's Escape key. Pointer coordinates come from the current
source-window drag event when available, including synthetic drags.

The native regression covers edge settling, crossing the page center, side
changes, re-entry, tolerance, preview-only release, actual mouse tracking,
horizontal and vertical strip extraction, and unchanged live page/form state:

```sh
python3 scripts/verify_drag_intent.py --app build-verify/platform/macos/Slate.app --log /tmp/slate-drag.log
```

Use a build configured with `-DSLATE_ENABLE_VERIFY=ON` for native regressions;
production builds exclude their command interface.
