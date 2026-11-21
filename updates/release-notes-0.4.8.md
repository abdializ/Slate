# Slate 0.4.8

- Fix Import Browser Data sheet getting stuck open (controller was deallocated under ARC before Cancel/Import could fire) and dismiss cleanly before showing the completion summary.
- Make browser importing work reliably inside macOS App Sandbox with pre-targeted folder access for Google Chrome, Dia, Arc, Brave, and Microsoft Edge, plus Bookmarks HTML and expanded Passwords CSV support (Chrome, Safari, 1Password, Bitwarden, Brave, Edge).
- Safely copy SQLite History databases into a temporary file before querying so importing works even while the source browser is open.

Restart Slate after updating.
