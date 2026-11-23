# Slate 0.4.19

- **Stop Delete/Backspace from navigating back:** Disabled WebKit's legacy `_backspaceKeyNavigationEnabled` preference on all `WKWebView` tabs so pressing Delete/Backspace in web apps and games (such as Wordle) deletes characters instead of navigating to the previous page. Back/Forward shortcuts (`⌘[` / `⌘]`, `⌘←` / `⌘→`), trackpad swipes, and toolbar buttons remain unchanged.
