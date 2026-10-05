# Memory pressure and protection observations

This milestone supplies the inputs for adaptive resource management. It does
**not enable automatic unloading**. ResourceController proposals are logged but
never passed to the browser close path. Manual unloading remains a confirmed,
user-requested operation, with the existing state-loss warning.

## Native memory monitor

The macOS implementation registers a dispatch memory-pressure source on the main
queue for Normal, Warning and Critical changes. A system query seeds the initial
level when available; an unavailable level remains Unknown. A 10-second timer
refreshes the main-process physical footprint and requests protection reports.
The monitor cancels its sources and suppresses pending callbacks during shutdown.

The status bar shows system pressure. Its tooltip and diagnostic log identify
main-process footprint explicitly: this excludes renderer, GPU and utility
processes and must not be called total browser memory. No artificial memory load
is generated to test system pressure.

## Runtime protection signals

- Keep loaded: user preference, persisted with the tab.
- Page interaction: native pointer/key activity in the document area. Sticky
  until a new main document commits; a conservative proxy, not a dirty-form API.
- Forms/editable content: renderer DOM observation, including untouched controls.
- Media elements: audio/video presence, protected even when paused.
- Camera/microphone use and media permission requests: native CEF callbacks.
  Existing Alloy permission behavior is preserved; nothing is auto-granted.
- Downloads: IDs tracked through CEF progress/completion/cancellation callbacks.
  Existing Alloy download cancellation remains unchanged; no download UI added.
- Beforeunload dialog: protected while the Stay/Leave decision is pending.
- Unknown: initial, missing, expired or failed observations, complex documents,
  loading and renderer failure.

Each CEF helper keeps the official sandbox entry sequence and adds a renderer
handler. Browser-to-renderer probes visit the DOM natively; no page-world bridge,
remote debugging port, or injected JavaScript is used. Replies contain an opaque
request token and three booleans only. Form values and document text are not
sent to the browser process.

Only replies from the current main frame, matching the latest request, are
accepted. Navigation invalidates pending requests; document generations prevent
old native observations from clearing a newer document's state. Reports expire
after 30 seconds. Closing a browser clears its runtime observations before a
replacement renderer starts its own generation counter.

A DOM traversal stops after 10,000 nodes and treats truncation as Unknown. Scripts,
iframes, canvas, embedded objects, SVG, custom elements and inline event handlers
make a document uncertain. Forms, media and complexity are sticky for the life
of the current document, even if a later snapshot no longer sees their elements.
Hovering a sidebar entry shows its current protection reason. These checks do not
read whether a form is saved; they protect the entire category conservatively.

## Why automatic unloading is still off

Snapshot-based observation cannot establish a universal guarantee about page
state. Script elements can disappear before the first probe, event handlers can
be registered programmatically, closed shadow roots can hide controls, and Web
Audio/capture and application-specific editing can outlive visible elements.
Native interaction tracking reduces this risk but is not complete state recovery.
“No blocker observed” therefore does not mean “safe to destroy without loss.”

The next milestone needs an explicit automatic-unload eligibility contract,
last-moment revalidation and cancellation, broader capture/audio/editing coverage,
and process-tree memory measurements. Do not enable a timer that directly closes
tabs based only on these snapshots. Selected, pinned, unknown, stale, loading,
interactive, form/media and active-operation tabs must remain protected.
