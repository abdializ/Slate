# Slate 0.4.13

- Fix Show, Copy, and Edit in the Passwords vault silently failing after Touch ID / macOS authentication (the `LocalAuthentication` reply fired while `NSApp.isActive` was still transitioning back from the system Touch ID prompt).

Restart Slate after updating.
