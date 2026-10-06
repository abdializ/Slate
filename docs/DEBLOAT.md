# Resource overhead improvements — October 6, 2026

Implemented in the downloaded Slate-main source. The production app remains a native AppKit/WebKit browser and restores saved tab metadata lazily.

## Bounded favicon pipeline

Previously each completed navigation created an ephemeral URLSession without invalidating it, downloaded arbitrary icon bytes into memory, and retained the original image in the tab UI. The new application-wide loader uses one ephemeral session with no disk cache, cookies, or credential storage. Navigation and tab closure cancel the tab's request, and navigation generations reject late results.

| Resource | Enforced limit |
| --- | --- |
| Active network tasks | 4 across the application, including cancelled tasks awaiting completion |
| Waiting requests | 128; oldest waiting request is cancelled when full |
| Response buffer | 256 KiB per active task; checked for advertised and streamed lengths |
| Decoded thumbnail | At most 64 pixels on either axis, first image frame only |
| Source image dimensions | At most 4096 on either axis and 4,194,304 pixels total |
| Cached PNG bytes | At most 2 MiB and 128 entries, explicit least-recently-used eviction |
| Request duration | 4-second request timeout, 6-second resource timeout |
| Redirects / URL length | 5 redirects, HTTP(S) only, at most 8192 URL characters |

Queued jobs reuse icons cached while they waited. Private requests neither read nor populate the cache. Memory-pressure warnings and critical events clear the icon cache. These limits bound Slate-owned icon buffers and cache entries; they do not bound all Foundation networking or ImageIO internal allocations.

## Page monitoring and close cleanup

Media detection now uses live audio/video collections, coalesces mutation bursts into one check per 100 ms, and avoids mutation checks entirely on media-free pages. Playback and PiP events still report immediately. Detached players do not remain retained as primary media; pending work is cancelled on page-cache entry and state is refreshed on return.

Theme monitoring disconnects its DOM observer and cancels all its timers when a document is hidden or enters the page cache. Foregrounding reconnects and reads the current theme. Visible documents retain the existing periodic fallback for CSS-driven color changes.

Closing a WebKit engine cancels icon work, clears media-frame metadata, disconnects the delegate's callback pointer, removes user scripts and handlers, and releases the delegate. It no longer starts an unnecessary blank-document navigation during teardown.

## Preservation boundary

The downloaded application had connected the automatic discard policy even though the adapter reports incomplete protection observations. This change disconnects automatic destruction, matching RESOURCE_SAFETY.md. Memory pressure evicts the bounded icon cache; it does not destroy edited pages, playback, calls or download tabs. Manual unloading still requires the existing state-loss confirmation. WebKit's general page memory and process management remain under WebKit and macOS control; the base occlusion/trim hooks do not imply browser-specific reclamation.

## Validation

All 23 CTest checks passed. Additional native favicon checks cover byte and queue caps, private cache bypass, cache-pressure eviction, actual LRU eviction, invalid URLs, cancellation, and service release after session invalidation and autorelease-pool drainage.

| Focused fixture | Before | After |
| --- | --- | --- |
| 1,000 media-page DOM mutation callbacks in one burst | 4,000 layout reads | 4 layout reads |
| 512 × 512 RGBA favicon retained at tab scale | 1,048,576 decoded bytes | 16,384 decoded bytes at 64 × 64 |
| Hidden theme monitor, 1,000 mutations plus 60 simulated seconds | Not compared | 0 layout reads, 0 timers |

The mutation fixture reduces layout reads by 99.9%; the icon fixture reduces decoded storage 64-fold. These are component measurements, not whole-browser CPU or RAM reductions. The unit fixtures also verify normal playback/PiP behavior, ad transitions, hidden-to-visible updates, and page-cache return.

WebKit itself recommends reducing script work and allocation churn to reduce CPU and garbage collection: [How Web Content Can Affect Power Usage](https://webkit.org/blog/8970/how-web-content-can-affect-power-usage/).

A verification-only measurement barrier now allows up to ten minutes for physical-footprint inspection instead of two minutes. This is excluded from production builds. Whole-browser comparisons must include WebKit helper processes and repeated, matched workloads; no universal market-leadership claim is established by these changes.

## Whole-browser validation on October 6, 2026

Three fresh-profile Slate trials used the existing benchmark's local workload: 24 same-origin documents, each with 1,500 rows and a touched 2 MiB array. Each condition received two physical-footprint samples, covering the attributed native and WebKit content/network process group in one footprint invocation. The machine was an Apple M3 Pro with 18 GiB RAM on macOS 27.0. System pressure was normal for every accepted sample.

| Condition | Median of trial medians | Trial-median range |
| --- | --- | --- |
| 24 saved logical tabs, 1 loaded page | 182.870 MiB | 182.800–183.035 MiB |
| 24 saved logical tabs, 24 loaded pages | 1,117.805 MiB | 1,115.860–1,119.664 MiB |

All 90 warm workspace switches preserved views, edited fields and JavaScript state, with no unexpected navigation. Median synchronous switch activation was 6.410 ms; this excludes display scanout and paint. The final source also passed the independent native regression's 47 switches, form continuity, declined-PiP timeout and graceful shutdown checks after the page-cache republication fix.

[Sanitized measurements](benchmarks/2026-10-06-debloat-slate.json) identify the measured verification binary by hash. A small later correction forces an unchanged media frame to republish on page-cache return; it does not affect this workload, and received the separate final native/regression checks. Production excludes verification commands and preserves the previously installed app's ad-hoc signing mode and bundle identifier.

These are current-build measurements, not matched before/after whole-browser savings. The browser-comparison attempts were rejected for invalid phase/loading conditions, so partial results do not establish a new Chrome comparison or market ranking. Real websites, long sessions, calls, video, energy use and multiple competing browsers still require matched repeated measurements.
