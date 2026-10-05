# Resource lifecycle and safety

Slate's resource goal is to keep a large tab workspace available without requiring every saved tab to have a live page. The current macOS application uses AppKit and WebKit. This document describes the current implementation and the work required before enabling automatic unloading.

## Logical tabs and live pages

`core/tab_model.cc` owns logical tab IDs, selection, grouping, pinning, and Keep loaded preferences. The native application separately owns live WebKit engines and their views. A tab record can exist without a running page.

`platform/macos/session_store.mm` restores tab records as unloaded. The application activates the selected workspace, including a split partner when needed; other pages load on selection. Session files retain tab metadata and do not serialize form values, JavaScript heaps, navigation history, or a full running document.

A switch between loaded workspaces reuses existing page views. The split-switch regression checks view identity, visible page hit targets, edited form fields, and in-page JavaScript state. This is continuity during switching, not lossless restoration after a page has been destroyed.

## Manual unloading

Unloading is a confirmed user operation. The native UI warns that form entries, scrolling, playback, and page history may be lost. The tab's address and title remain available, and restoring reloads the URL. Keep loaded prevents the normal manual unload action.

Automatic unloading remains disabled. No timer or memory-pressure callback automatically destroys a page in the current application.

## Resource policy and protection

`core/resource_controller.cc` is a pure policy: it proposes Active, Warm, Cold, Discarded, or Protected states without creating or destroying engines. Its protection model covers Keep loaded, PiP, page interaction, observation freshness, loading, uncertain state, forms, media, capture, permission requests, downloads, and dialogs.

Those policy fields are not evidence that the current WebKit adapter detects every condition reliably. Its protection inspection does not establish complete DOM or application-state coverage. The automatic controller must remain disconnected until the engine supplies trustworthy observations and the lifecycle path handles races and cancellation.

A hidden page is still a loaded page. Cold is a policy state, not a claim that WebKit has frozen a renderer. The WebKit adapter does not currently implement the base engine's occlusion or memory-trim hooks as a browser-specific resource reclamation mechanism.

## Memory measurement

The macOS memory monitor observes system pressure and the native application's physical footprint. That footprint excludes WebKit's separate content and networking processes. It must not be described as total browser memory.

Warning and critical pressure currently request engine occlusion synchronization and memory trimming through the engine interface; these hooks do not unload pages and do not demonstrate measured WebKit memory savings.

The first [tab workspace benchmark](BENCHMARKS.md) measures identified browser process groups across three fresh-profile runs, separating fully loaded and lazy-restored workspaces. It reports variation, loaded-page count, pressure, and timing boundaries. Its synthetic same-origin results do not establish a general advantage on real websites.

Any comparative memory claim must continue to include the whole browser with a repeatable workload, comparable settings, warm-up, and repeated runs. Report variation, loaded-page count, restore latency, and macOS shared/compressed-memory caveats. Do not treat summed RSS as unique physical memory.

## Requirements before automatic unloading

- Define a narrow, explicit eligibility contract. Selected, Keep loaded, editing, media, capture, download, dialog, loading, unknown, and stale tabs must remain protected.
- Revalidate immediately before destruction and cancel when state changes, navigation races, or the page refuses to close.
- Distinguish a live-page switch from a restore that reloads a URL. Make any potential state loss visible to the user.
- Test complex documents, cross-frame media, delayed observations, shutdown, and session recovery.
- Demonstrate resource savings and acceptable restore latency without unexpected loss of supported page state.

Until those requirements are met, manual control and preservation of already loaded pages are the supported behaviors.
