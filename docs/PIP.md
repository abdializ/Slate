# Native Picture-in-Picture (PiP) Architecture in Slate

Slate implements production-grade, native Picture-in-Picture (PiP) support for macOS, engineered to match the seamless, high-performance behavior of Safari.

---

## 1. Architectural Principles

Picture-in-Picture in Slate is built strictly on top of macOS WebKit and AVKit primitives, adhering to these fundamental rules:

1. **WKWebView as Single Source of Truth**:
   The `WKWebView` instance that initiated the media playback remains the sole owner of the media pipeline. Slate never extracts raw video stream URLs, never spins up separate `AVPlayer` instances, and never constructs custom floating `NSWindow` overlay players.
2. **Full DRM, EME & Session Compatibility**:
   By keeping the media playback within the originating WebKit engine, full compatibility is preserved for Encrypted Media Extensions (EME / DRM), Media Source Extensions (MSE), authenticated cookie sessions, HTTP live streaming (HLS), and custom web players (YouTube, Netflix, Disney+, Prime Video, Twitch, Vimeo).
3. **Native WindowServer Presentation**:
   macOS WindowServer and AVKit manage the floating window directly. The floating window floats across all spaces, snaps to screen corners, supports standard system pinch/drag gestures, and presents system controls.
4. **Tab Discard & Occlusion Immunity**:
   Tabs actively presenting video in PiP are protected from background tab discarding and GPU occlusion suspension.

---

## 2. WebKit Native PiP Pipeline

```
┌────────────────────────────────────────────────────────────────┐
│                       Website / Web Player                     │
│   (PiP button/⌥⌘P, tab switch, or leaving a playing tab)       │
└───────────────────────────────┬────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────┐
│                   WebKit Video Presentation Mode               │
│        video.requestPictureInPicture()                         │
│        or video.webkitSetPresentationMode('picture-in-picture')│
└───────────────────────────────┬────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────┐
│                macOS WindowServer & AVKit Layer                │
│  - System floating PiP window appears over all spaces          │
│  - Native resize, corner-snap, play/pause, return & close      │
└───────────────────────────────┬────────────────────────────────┘
                                │ DOM events:
                                │ 'enterpictureinpicture'
                                │ 'leavepictureinpicture'
                                │ 'webkitpresentationmodechanged'
                                ▼
┌────────────────────────────────────────────────────────────────┐
│            WebKitEngine Script Bridge (slatePiP)               │
│  - Injected monitor in defaultClientWorld                      │
│  - Reports state: window.webkit.messageHandlers.slatePiP       │
└───────────────────────────────┬────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────┐
│                   EngineEvents::pip_changed                    │
│  - Updates Tab::pip_active in ResourceController / TabModel    │
│  - Updates RuntimeTab::pip_active in macOS main.mm             │
│  - Displays `pip.fill` badge on tab pills and sidebar rows     │
│  - Prevents occlusion and protects tab from memory discard     │
│  - On exit: clears PiP state without stealing app focus        │
└────────────────────────────────────────────────────────────────┘
```

### Injected Media Monitor (`mediaMonitorJs`)
In `engine/webkit_engine.mm`, Slate injects an isolated script into `[WKContentWorld defaultClientWorld]` that tracks all `<video>` elements on the page:

```javascript
function sendPipState(active) {
  try {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.slatePiP) {
      window.webkit.messageHandlers.slatePiP.postMessage({ active: !!active });
    }
  } catch (e) {}
}

video.addEventListener('enterpictureinpicture', function() { sendPipState(true); });
video.addEventListener('leavepictureinpicture', function() { sendPipState(false); });
video.addEventListener('webkitpresentationmodechanged', function(e) {
  var mode = (e && e.target) ? e.target.webkitPresentationMode : video.webkitPresentationMode;
  sendPipState(mode === 'picture-in-picture');
});
```

---

## 3. Background Playback & Occlusion Management

After the user starts a visible video, switching tabs, minimizing Slate, or moving to another app requests native PiP. A page that merely autoplays media does not trigger it. Returning to the video tab or Slate ends automatically entered PiP; PiP opened manually stays open until the user closes it. If the user closes automatic PiP, Slate suppresses another automatic request for that playback session. A pending PiP request keeps its WebKit view active until presentation succeeds or times out.

In standard WebKit tab architectures, hiding a tab's view (`host.hidden = YES`) or marking it occluded suspends compositor tile generation and can throttle timers. For Picture-in-Picture:

1. **Persistent View Hierarchy**:
   When switching away from a tab with an active PiP session, the web view is hidden from the main content viewport but remains attached to the window's view hierarchy.
2. **Occlusion Bypass**:
   `syncBrowserOcclusion` in `platform/macos/main.mm` inspects `item.pip_active`:
   ```objc
   for (SlateTabItem* item in self.tabItems) {
     if (item.engine) {
       // PiP tabs must NEVER be marked occluded, allowing smooth background playback
       BOOL occluded = (item != self.activeItem && !item.pip_active);
       item.engine->set_occluded(occluded);
     }
   }
   ```
   This ensures WebKit continues rendering video frames into the WindowServer PiP surface without dropouts, even when the browser window is minimized or covered by other applications.

---

## 4. Resource Safety & Tab Discard Immunity

Under low-memory pressure, Slate's `ResourceController` aggressively unloads inactive tabs. A video playing in PiP must never be discarded:

- `core/resource_controller.h` tab structure includes:
  ```cpp
  bool pip_active = false;
  ```
- In `core/resource_controller.cc`:
  ```cpp
  if (tab.pip_active || tab.audible || tab.media_playing) {
    tab.lifecycle = Lifecycle::Protected;
    tab.protected_reasons.push_back(ProtectedReason::MediaPlaying);
    continue;
  }
  ```
  Tabs with `pip_active == true` are classified as `Lifecycle::Protected` and are completely skipped during critical memory discard sweeps.

---

## 5. Return-to-Tab Mechanism

When PiP ends, WebKit reports the transition and Slate clears the tab's PiP badge and resource protection. Closing the PiP window does not raise Slate or change tabs; a close must not cover the app the user is viewing. The native PiP window provides its own Return to Tab control.

---

## 6. Clean Teardown on Tab Close

When a user closes a tab that has an active PiP window, the browser must avoid orphaned WindowServer floating windows or memory leaks.

In `WebKitEngine::close()`:
```objc
if (web_view_) {
  [web_view_ closeAllMediaPresentationsWithCompletionHandler:^{
    // Media presentations dismissed cleanly before teardown
  }];
}
```
This guarantees all native floating presentations are cleanly dismissed prior to destroying the WebKit host.

---

## 7. User Interface & Controls

- **Omnibox PiP Button**: An intuitive Picture-in-Picture icon appears in the right accessory view of the address bar whenever a video is present on the page, toggling presentation mode.
- **Keyboard Shortcut**: `⌥⌘P` (Option + Command + P) triggers or exits native PiP.
- **Tab Indicators**:
  - Horizontal tab pills display a subtle `pip.fill` system badge alongside audio status.
  - Vertical sidebar rows feature a designated `pip.fill` indicator.
- **Native Context Menus**: Right-clicking any HTML5 video provides the system "Enter Picture-in-Picture" option supported out-of-the-box by WebKit.
