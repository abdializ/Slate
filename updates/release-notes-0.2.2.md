# Slate 0.2.2

- Fix Connect appearing unresponsive and the pairing code field staying hidden on supported builds.
- Show connection progress, immediate helper errors, and a Cancel action while pairing.
- Explain Apple's browser-approval restriction before attempting an unavailable connection on recent macOS versions.
- Stop offering Apple Passwords when the current Slate build cannot connect, and provide an Open Apple Passwords action.

Direct Apple Passwords connection on recent macOS still requires Apple's browser entitlement approval and a correctly provisioned signed Slate build. This release does not grant that approval.
