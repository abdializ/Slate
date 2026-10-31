# Slate 0.4.1

- Fix the missing system PiP service permission in sandboxed 0.4 builds. This prevented the live video handoff to the picture-in-picture window.
- Fix the same build's updater connection permissions and enable Sparkle's installer service when the app is signed with App Sandbox.
- Validate the effective signed permissions before preparing an update, so an incomplete sandbox configuration cannot be published again.
- Add a real macOS regression that reproduces the old denied PiP connection and confirms the corrected policy reaches the service while unrelated services remain blocked.

The 0.4 omnibox and search features are retained. Restart Slate after installing this fix.
