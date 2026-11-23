# Slate 0.5.4

- **Live macOS Menu Bar `Extensions` Menu with Per-Site Allow / Don't Allow Controls:**
  - Clicking **Extensions** in the top macOS menu bar now lists every installed Chrome extension (with its icon and badge) alongside the master **Enable Chrome Extensions** toggle and **Manage Extensions…** shortcut.
  - Each extension submenu provides instant controls for the active tab: **Open Popup**, **Open Side Panel**, **Options…**, **Allow on `<site>`**, **Don’t Allow on `<site>`** (persisted per-host via WebKit's `WKWebExtensionContext` match patterns and applied immediately), **Enabled**, **Allow in Incognito**, and **Remove Extension**.
