# Tab previews and Control-Tab

Slate's native AppKit switcher adapts the supplied SwiftUI `TabSwitcher` and
`TabSwitcherOverlay` design to Slate's existing WebKit runtimes.

Hold Control and press Tab to reveal a centered panel of page previews, with five
cards per row and up to ten recent main-window tabs. Detached tabs appear in a
smaller panel beside it, in balanced columns of up to three cards, with up to nine
cards. A split pair occupies one card with its pages pictured side by side and
returns to its previously active pane. Detached cards scale with page length.

A quick Control-Tab switches directly to the tab last left. The panel appears
after 150 ms when Control stays down. Repeated Tab presses keep the gesture's
initial order; Shift-Tab walks backwards. Releasing Control commits the selection.
Arrow keys move between cards. Enter picks the highlighted card, and Escape or a
click outside the panels cancels. Moving the mouse selects a card; a stationary
pointer does not override the keyboard selection. Clicking a card picks it.

While Control is held, W closes the highlighted tab, R reloads its existing page,
and M toggles mute. O moves a highlighted detached tab to the main browser window.
These actions use Slate's existing lifecycle, close handling, and audio controls.
The regular next/previous-tab menu commands remain available for the full tab row.

## Page and memory behavior

The switcher never creates a WebKit view to take a preview. Saved or unloaded tabs
show their site icon until they have a live page. Images are captured at a width
of 180 points, kept only in memory, checked against their page address, and bounded
to the ten recently left tabs plus the cards in the open gesture. Closing the
panel drops images outside that recent set. Stale asynchronous captures are
ignored after cancellation, a new gesture, a space change, or address changes.

Each space retains its own recent ordering. Changing spaces cancels the switcher
and clears cached images, so a reused tab ID cannot show another space's page.
Switching reuses Slate's existing live views and preserves their document state.
The port does not change Slate's unloading or session-restoration policies.

## Implementation and verification

- `core/tab_switcher.h` contains deterministic gesture ordering and grid navigation.
- `platform/macos/tab_switcher.mm` draws the panels, handles input, and manages previews.
- The owner bridge in `platform/macos/main.mm` supplies tab metadata, existing page
  snapshots, split membership, and actions.

Run `ctest --test-dir build --output-on-failure` for the unit suite. A verification
build also supports:

```sh
cmake -S . -B build-verify -DCMAKE_BUILD_TYPE=Release -DSLATE_ENABLE_VERIFY=ON
cmake --build build-verify -j 4
python3 scripts/verify_tab_switcher.py --app build-verify/platform/macos/Slate.app --log /tmp/slate-switcher.log
```

The native regression uses a temporary profile and loopback fixture pages. It
checks recent ordering, quick switching, held gestures, arrows, cancellation,
mouse hover/click, split pairs, detached windows, closing a highlighted card,
preserved form edits, and that previewing unloaded tabs does not load pages.
Verification commands are excluded from default production builds.
