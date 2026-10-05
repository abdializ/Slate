# UI repair notes — September 22, 2026

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
