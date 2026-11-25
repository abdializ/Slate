# Slate 0.5.22

## WebContent & Main-Process Memory Lock-In
- **Lean WebKit Process Pool**: Configured `WKProcessPool` with `usesWebProcessCache = NO` and aggressive memory-pressure process suspension so closed or navigated tabs never linger as zombie WebContent processes.
- **Cross-Process Memory Cache & JSC GC Sweeps**: Added `PurgeWebKitMemoryCaches()` using Apple's public `WKWebsiteDataTypeMemoryCache` eviction (across default, per-Space, and incognito stores) plus WebKit process-cache clearing and periodic JavaScript garbage collection — reclaiming dead decoded images, scripts, stylesheets, and JS objects without touching logins, cookies, or active playback.
- **BFCache & Subframe Script Diet**: Capped WebKit Back/Forward cache retention on deep SPA navigation and restricted main-frame-only helper scripts (`kMemoryOptimizerJs`, `chromeCompatJs`, `kExtensionShimsJs`, `kTwitchAdBlockJs`) to stop spinning up redundant JS worlds inside nested iframes.
- **Streaming Buffer Cap**: Capped `novahd.cc` player HLS buffer config (`bufferTargetSeconds <= 15s`, `maxBufferSeconds <= 25s`), cutting live media buffer RAM by ~55–60% without affecting playback smoothness.
- **Tighter Main-Process Trim & Smart Auto-Sleep**: Deferred cold `SlateShields` rule compilation by 1.5s so temporary compiler allocations don't fragment launch memory, tightened `trim_process_memory` thresholds (`80 MB` / `85 MB`), added a `5 minutes` Smart Auto-Sleep option, and lowered the default idle-sleep timeout from `30` → `10` minutes (`5` minutes when >4 tabs are awake).
