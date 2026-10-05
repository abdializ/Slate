# Slate Architecture

Target: Apple Silicon macOS (Universal / arm64), macOS 13.0+.

Slate is a high-performance, security-hardened, and lightweight macOS browser designed around native WebKit and modern AppKit chrome.

---

## 1. Core Architecture Overview

```text
┌─────────────────────────────────────────────────────────────┐
│                 AppKit Native Chrome Shell                  │
│  (Window, Titlebar, Vertical/Horizontal Tabs, Omnibox, PIP) │
└──────────────┬───────────────────────────────┬──────────────┘
               │                               │
       ┌───────▼────────┐             ┌────────▼────────┐
       │ Slate Core C++ │             │ Platform Panels │
       │  - TabModel    │             │  - Bookmarks    │
       │  - Credentials │             │  - Passwords    │
       │  - Navigation  │             │  - Downloads    │
       │  - Shields     │             │  - Spaces       │
       │  - Sessions    │             │  - Site Cards   │
       │  - Memory      │             │  - Floating PIP │
       └───────┬────────┘             └────────┬────────┘
               │                               │
┌──────────────▼───────────────────────────────▼──────────────┐
│                  Native WebKit Engine Layer                 │
│  - WKWebView / WebKitEngine (Process-isolated, Out-of-Proc) │
│  - Strict App Sandbox & Hardened Runtime                    │
│  - In-Process Network Shields (EasyList, EasyPrivacy)       │
│  - DOM Video Isolation & Picture-in-Picture Engine          │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Directory Layout & Organization

The repository is organized cleanly by responsibility:

- **`core/`**: Platform-independent C++ browser logic:
  - `tab_model.{h,cc}`: Logical tab hierarchy, lifecycle states, tab groups, pins.
  - `credential_store.{h,cc}`: Secure in-memory password store and origin matching.
  - `navigation.{h,cc}`: Address-bar input parser, search vs URL classifier, scheme safety.
  - `shields.{h,cc}`: Content blocker rules engine and tracking prevention policy.
  - `library.{h,cc}`: Bookmarks and history data models.
  - `resource_controller.{h,cc}`: Tab memory lifecycle and unload recommendations.
- **`engine/`**: Web rendering and media engine bridges:
  - `webkit_engine.{h,mm}`: Out-of-process WebKit engine host and event dispatcher.
  - `engine_events.h`: Common engine event contracts and callbacks.
  - `webkit_shields.{h,mm}`: WKContentRuleList network shield compiler.
  - `floating_video_js.h`: Picture-in-Picture CSS isolation and DOM defense scripts.
  - `autofill_js.h` & `page_chrome_js.h`: Script injection for password autofill & page styling.
  - `platform_audio.{h,mm}`: AudioToolbox hardware-accelerated media decoders.
- **`platform/macos/`**: Native macOS AppKit UI and system integrations:
  - `main.mm`: App delegate, main window, omnibox, tab bars, shortcuts, menus, and native PiP bridge.
  - `bookmarks_panel.{h,mm}` & `bookmark_store.{h,mm}`: Native bookmarks manager and persistence.
  - `passwords_panel.{h,mm}` & `credential_persistence.{h,mm}`: Keychain-backed password manager.
  - `downloads_panel.{h,mm}` & `download_manager.{h,mm}`: Quarantine-safe download pipeline.
  - `spaces_manager.{h,mm}`: Workspaces and parked tab sessions.
  - `site_card_panel.{h,mm}`: Domain identity, certificate inspector, and permission hub.
  - `settings_panel.{h,mm}`: Appearance, accent colors, granite intensity, and preferences.
  - `plate_components.{h,mm}`: Native styling, glass vibrancy, and custom drawing components.
- **`filtering/`**:
  - `network_engine.{h,cc}`: High-speed URL matcher for network requests.
  - `lists/`: Bundled EasyList and EasyPrivacy rule extracts.
- **`tests/`**: Complete automated test suite:
  - Unit tests for core, tabs, navigation, shields, credentials, importer, sessions, audio, floating video.
  - `tests/fixtures/`: Local test HTML pages and audio/video files.
- **`scripts/`**:
  - `verify_security.py`: Comprehensive 5-phase security verification harness.
  - `codesign.sh`: Local development code signing script.
  - `package-shields.py`: Content blocker list packager.
  - `test-core.sh`: Core test runner.
- **`docs/`**: Feature architecture specifications and validation reports.

---

## 3. Native Picture-in-Picture (PiP) Architecture

Slate features a production-grade native Picture-in-Picture architecture using macOS WebKit and AVKit WindowServer integration:

1. **WKWebView Single Source of Truth**:
   The `WKWebView` instance that plays the video owns the entire media pipeline, maintaining strict compatibility with DRM/EME (Widevine, FairPlay), MSE, authenticated sessions, and custom web player controls.
2. **Native WindowServer Presentation**:
   PiP uses `video.requestPictureInPicture()` and `video.webkitSetPresentationMode('picture-in-picture')`, managed directly by macOS WindowServer across all virtual desktops and spaces with corner snapping and native controls.
3. **Continuous Background Playback**:
   When switching tabs or minimizing the browser window, tabs with active PiP remain attached to the view hierarchy and bypass compositor occlusion (`item.engine->set_occluded(NO)`), guaranteeing uninterrupted playback.
4. **Tab Discard Immunity**:
   Tabs with `pip_active == true` transition to `Lifecycle::Protected` in `ResourceController` and are immune to tab discard under critical memory pressure.
5. **Safari-Style Return to Tab**:
   Exiting PiP or clicking the native return button automatically restores and focuses the Slate window and activates the originating tab.
6. **Clean Teardown**:
   Closing a tab cleanly invokes `closeAllMediaPresentationsWithCompletionHandler:` to dismiss native presentations without dangling references.
