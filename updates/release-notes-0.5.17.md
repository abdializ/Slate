# Slate 0.5.17

## Memory & Performance Optimizer
- **Heavy-Site Idle Memory Optimizer (Kick, YouTube, Twitch, X, Reddit):** Runs in isolated `WKContentWorld.defaultClientWorld` strictly on idle ticks (zero foreground video impact):
  - Caps live chat DOM growth to the newest 140 messages on Kick, Twitch, and YouTube Live (only when scrolled near the bottom so chat scrollback is never disrupted).
  - Pauses scrolled-past offscreen feed preview `<video>` decoders on YouTube/X/Reddit/Kick.
  - Suspends hidden muted background streams on tab switch and resumes seamlessly on return while leaving audible background media completely uninterrupted.
- **WebKit GPU Tile, Back/Forward Cache & Teardown Trimming:**
  - Disabled aggressive offscreen GPU tile retention (`_setAggressiveTileRetentionEnabled:NO`), prevented invisible autoplay decoding (`_setInvisibleMediaAutoplayNotPermitted:YES`), and enabled native window occlusion detection (`_setWindowOcclusionDetectionEnabled:YES`).
  - Implemented `set_occluded()` and `trim_memory()` in `webkit_engine.mm` to purge suspended Back/Forward page snapshots (`_clearBackForwardCache`) and run idle page trims, plus clean `_close` teardown on unload/close.
- **Main-Process Malloc Pressure Relief:** Reclaims dirty freed `malloc` pages (`malloc_zone_pressure_relief`) off the main thread after compiling adblock rule lists, on app backgrounding, on tab unload, and under macOS memory warnings.
- **Smart Auto-Sleep Idle Tabs + Settings Controls:** Added a **Memory & Performance** section in Settings → General with **Optimize Heavy Sites**, **Auto-Sleep Idle Tabs** (Off / 10 min / 30 min default / 1 hr / 2 hr — protecting audio, video, PiP, active downloads, pinned tabs, and split panes), and a **Trim Now** button.
