# Slate 0.5.2

- **Chrome WebExtension API Compatibility Shims (Phase 3):**
  - Added native macOS WebKit bridges for Chrome-only extension APIs (`chrome.offscreen` via hidden shared-controller `WKWebView`, `chrome.sidePanel` via a native `SlateExtensionSidePanel` viewer, `chrome.identity.launchWebAuthFlow` via OAuth popup sheet with `*.chromiumapp.org` redirect capture, `chrome.notifications` via `UserNotifications`, `chrome.runtime.getPlatformInfo`, and safe `idle`/`management` stubs).
  - Upgraded `manifest.json` normalization to strip Chrome-only manifest keys (`minimum_chrome_version`, `cross_origin_*`, MV3 `background.persistent`) and preserve `side_panel.default_path`.
  - Added right-click context menus on toolbar extension icons (**Open Side Panel**, **Options**, **Manage Extensions…**, **Remove**) and a **Side Panel** button in Settings → Extensions.
