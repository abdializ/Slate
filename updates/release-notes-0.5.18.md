# Slate 0.5.18

## Critical Main-Process Memory Fix
- Fixed Slate's main UI process holding **1.5–1.7 GB** of empty freed `malloc` pages (`Malloc Large (empty)` / `DefaultMallocZone` fragmentation) after `WKWebExtensionController` compiles Chrome extension `declarativeNetRequest` filter lists (such as Pie Adblock) at startup or during background filter updates.
- Added all-zone `malloc_zone_pressure_relief` reclamation with a self-terminating post-compilation settle watcher that returns empty pages to macOS within seconds of rule compilation finishing (dropping steady-state main-process footprint from ~1.6 GB down to ~120–150 MB) and stops completely at idle.
- Assigned each extension a deterministic `webkit-extension://<id>/` base URL across launches so extensions retain their `IndexedDB`, `localStorage`, and service worker state instead of re-syncing filter lists from scratch on every startup, and granted `declarativeNetRequestWithHostAccess` for DNR extensions.
