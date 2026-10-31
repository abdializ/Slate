# UI repair notes

> **File notes:** Records native interface fixes and their verification context.


## October 6, 2026 — Distinguish split intent from window tear-off

Dragging through the page no longer treats either entire half as a new split
target. Hold over a visible left/right split target for 350 ms to arm it;
the label changes from “Hold here to split” to “Release to split”. Movement
beyond 14 points before arming restarts the hold, while small hand jitter is
accepted. Leaving the target, switching sides, re-entering or starting a new
drag clears the armed choice. A normal release away from the tab bar detaches
the tab, including releases inside the source window.

Tab-on-tab splits also require a deliberate hold; quick passes retain reorder
behavior. Returning to the tab bar cancels tear-off, and Escape cancels the
horizontal tracking gesture. Existing empty split panes still accept a deliberate
hold and drop. Native accepted drops remain processed once. The stationary
horizontal pointer is sampled only while dragging; the vertical path reuses its
existing drag timer, and no background timer remains after a gesture.

Validation: 24 CTest checks, 14 native intent checks in both layouts, seven
actual mouse-tracking checks, two deliberate sidebar/page split drops, 37 window
checks plus restart, and 47 split switches passed. These cover quick release,
left/right holds, leaving an armed target, switching sides, re-entry, returning
to the bar and Escape. Existing page views, JavaScript and edited forms survived
without reload. Release builds passed, and verification hooks stay disabled in
the installed production app.

## October 6, 2026 — Detached windows with normal tab controls

Detached windows now own an ordered set of tabs, with Slate's existing tab
styles, a plus button, Command-T, local tab switching and per-tab closing.
Tabs can be reordered, moved between secondary windows, or returned to either
the original horizontal tab strip or vertical tab list. Moving the last tab
closes its empty secondary window; moving one of several leaves the others open.

Transfers reparent the existing page view. They retain page history, JavaScript,
form contents and the tab's zoom instead of loading a duplicate page. Inactive
pages stay hidden. Window refreshes reuse tab controls and visit each secondary
window once, rather than once for every tab it contains.

Native tab-strip mouse events are routed to their controls before macOS handles
the title bar. Keyboard and menu actions stay bound to the event's window during
focus changes. Popups stay with their source window. Close cancellation and
unsaved-change dialogs also return to the owning window.

A drag away from the tab strip can detach the tab inside its source window;
it no longer has to cross the whole window boundary. Existing split-view drops
retain their handler and take precedence when a valid split target accepts them.

Validation:

- All 23 CTest checks passed.
- The isolated native window regression passed 37 checks plus restart, including
  actual mouse-event selection, in-window tear-off from both window types, the
  plus button, shortcuts, overflow, reorder, eight transfers and window closure.
  Existing page views, JavaScript and edited forms survived the transfers.
- The split regression passed 47 switches; its seven-check follow-up passed
  vertical row/page drops and native picture-in-picture transitions.
- Ten zoom checks plus restart and the WebKit/URLSession download feedback checks
  passed. Per-pane zoom remains independent.
- Live UI inspection exercised tab tear-off, plus, Command-T and navigation in a
  detached tab. Both Release builds passed. Verification commands and automated
  input filtering are disabled in the installed production build.

Window layouts are not persisted separately; the existing session format still
restores saved tabs into the original window.

## October 6, 2026 — Independent split zoom and interaction feedback

Command-plus/equal, Command-minus and Command-zero now change only the active
page. Each tab keeps its own 25–500% zoom level, including split panes and
separate tab windows. New tabs start at 100%. Zoom survives normal session
restoration and parking tabs in another space; legacy sessions default to 100%.
The previous application-wide zoom preference is retired.

A rounded native percentage indicator appears at the top right of the active
pane. It has a magnifier, a reset-to-100% button and an accessible percentage
announcement. Repeated shortcuts update the same indicator and restart its
single two-second dismissal timer. Switching panes hides it.

New WebKit and URLSession downloads send a dedicated start event. A short accent
comet travels to the visible download icon and ends in a light ring and six small
sparks. It targets the toolbar, vertical sidebar or detached window as appropriate.
The overlay passes clicks through, uses finite Core Animation effects, is removed
within one second and stays bounded to one effect per window during bursts.
Progress updates and restored download history do not replay the effect. Reduce
Motion uses a stationary fading highlight instead of flight or particles.

Validation:

- All 23 CTest checks passed, including tab isolation, zoom bounds, per-tab session
  round trips, legacy defaults and malformed-zoom preservation.
- The isolated native interaction regression passed ten zoom checks plus restart:
  independent panes, reset, swapped sides, a new tab, vertical layout and a
  detached window. Existing JavaScript state and edited form contents survived.
- Actual page-initiated WebKit downloads and four URLSession downloads completed.
  Feedback was visible in both toolbar layouts, passed clicks through, did not
  accumulate during a burst and disappeared after arrival.
- The existing native split regression passed 47 switches and preserved forms.
- Native visual inspection confirmed Command-equal in the left pane at 110%,
  Command-minus after clicking the right pane at 90%, and a comet traveling into
  the toolbar download icon.
- Both Release builds succeeded. The verification command runner is disabled in
  the installed production build.

## October 6, 2026 — Active New Tab toolbar overlap

An active New Tab (`about:blank`) painted two points below the horizontal tab
row. Its solid tab fill visibly overlapped the New Tab page's gradient toolbar.
The tab path now ends at the row boundary on New Tab pages. Normal webpages
retain their existing seamless toolbar join. Active split-group shapes use the
same rule when the selected page is a New Tab.

Validation:

- Release application build and strict code-signature verification passed.
- `active_tab_geometry` passed. Regression checks cover both drawing
  orientations and narrow, wide, and split-group widths, and verify that New Tab
  paths cannot paint above or below the tab row.
- Native UI checks confirmed a flush active New Tab edge and the existing
  toolbar join on a normal webpage. The tested build was installed locally.

## September 22, 2026

Changes applied on top of the existing uncommitted browser work:

- Collapsing vertical tabs explicitly hides the sidebar. Its internal scroll
  constraint can yield at zero width; the New Tab button no longer prevents
  collapse through competing required leading/trailing constraints.
- Tab orientation changes apply a single layout transaction instead of animating
  CEF host geometry. Browser size is synchronized after the native layout settles.
- Traffic-light placement uses the intended sidebar mode and a stable header
  anchor, without choosing anchors from stale bounds. All three native buttons
  are repositioned together and have no autoresizing mask. The toolbar reserves
  space for them when crossing between an icon rail and the expanded sidebar.
- Ordinary background tabs no longer wait 60 ms before being hidden. The existing
  delay remains for video tabs to preserve their picture-in-picture transition.
- Audio compatibility observes changed subtrees rather than rescanning the entire
  document after every mutation. Media reporting also avoids selecting the same
  video twice per report.
- The new-tab page hides the top address field. Command-L already focuses the
  center search input. The normal address field returns for a webpage.
- The start-page document now follows its scroll viewport during sidebar and
  orientation changes. Search width is bounded by the available space, and the
  greeting position uses viewport height. Same-tab transitions to/from the home
  page refresh its visibility and colors instead of taking the refresh fast path.

Validation:

- Release application build passes.
- All nine CTest suites pass with normal macOS codec access. The restricted
  runner cannot expose the AAC encoder; rerunning its audio test outside that
  restriction passes without changing the test or decoder.
- `node tests/audio_observer_tests.cjs` passes initial, unrelated-mutation,
  inserted/nested audio, already-bridged audio and source-change checks.
- Both edited embedded JavaScript programs pass syntax checks.
- Live isolated profile: hidden sidebar removed its controls from accessibility;
  horizontal tabs appeared without vertical rows; closing the example.com tab
  removed its entry; navigation loaded Example Domain; shutdown completed.
- Live screenshots from the control tool were miniature window images, so they
  did not support a reliable pixel-level comparison of traffic-light placement.
- No overall page-load benchmark or universal speedup is claimed. Startup still
  sometimes waits for macOS Keychain and logs a CEF network-service restart.

The final start-page adjustment was built and tested. After restart, the live
vertical new-tab page exposed only its center search input, with no top address
field, and focus was on that center input. Original saved tab data was preserved.
Existing uncommitted work was not bundled into a new commit.
