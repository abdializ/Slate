# Slate 0.5.0

- **Native Chrome Extensions on WebKit (Phase 1):**
  - Integrated Apple's native macOS 15.4+ `WKWebExtension` / `WKWebExtensionController` runtime into all Slate tabs with persistent extension storage, tab/window adapters (`WKWebExtensionWindow`, `WKWebExtensionTab`), and automatic permission wiring.
  - Added a built-in Chrome `.crx` (CRX3 & CRX2), `.zip`, and **Load Unpacked** folder installer with manifest normalization.
  - Added extension toolbar action buttons with native `NSPopover` popups and live badge tooltips right beside the toolbar controls.
  - Added a minimalist **Extensions** page in Settings (`⌘,` → Extensions) to install, enable/disable, allow in Incognito, open Options pages, and remove extensions.
