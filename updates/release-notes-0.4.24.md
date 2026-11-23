# Slate 0.4.24

- **Major macOS Power & Battery Optimization (lightweight without sacrificing speed):**
  - **Safari-grade WebKit background throttling:** Enabled `WKInactiveSchedulingPolicySuspend`, `_setDOMTimersThrottlingEnabled`, `_setHiddenPageDOMTimerThrottlingEnabled`, `_setHiddenPageDOMTimerThrottlingAutoIncreases` (progressive background timer backoff), and `_setLowPowerVideoAudioBufferSizeEnabled` on all tabs.
  - **Zero idle mouse wakeups:** Hover-to-peek sidebar global/local `NSEventMaskMouseMoved` monitors are now only active while the vertical sidebar is actually collapsed and Slate is visible/active, instead of waking Slate on every system-wide cursor movement.
  - **Coalesced background timers:** Reduced `MacMemoryMonitor` periodic sampling from 10s to 60s with 15s leeway (OS memory pressure events still fire immediately), increased New Tab greeting timer from 30s to 5 minutes with 30s tolerance (skipped when hidden), paused streaming/Yahoo ad-defuser observers when `document.hidden`, removed duplicate streaming defuser evaluation on Twitch, and relaxed Twitch buffering check polling from 600ms to 1500ms.
