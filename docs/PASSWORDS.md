# Saved passwords — September 24, 2026

This implements the saved-password interaction from the supplied Search project
in Slate's native AppKit UI. Open Slate > Saved in Slate (Option-Command-P).

The user clarified that Apple Passwords is the desired source. Slate > Open
Apple Passwords opens the system application, and the local panel is explicitly
labeled Saved in Slate. This launcher does not authorize reading the Apple vault
or implement automatic filling from it. General Apple Passwords integration is
still incomplete: the current WebKit app has no WKWebExtension/native-messaging
implementation and no stable Apple signing identity. Apple documents the iCloud
Passwords extension browser allowlist and OS-update requirement here:
https://github.com/apple/password-manager-resources#how-apple-uses-web-browser-extension-distribution-information

App-associated password access is not a general third-party browser vault API:
https://support.apple.com/guide/security/app-access-to-saved-passwords-sec8762eb992/web

Do not treat the generic-password Keychain item used below as Apple Passwords
access. Do not copy another browser identity or broaden Keychain groups to try
to obtain that access. Passkeys require a separate supported browser integration.

Implemented:
- Sites expand into account rows. Search matches sites and usernames.
- Add uses a secure password field. Existing site/account entries update.
- Show and Copy each request macOS device-owner authentication, with no
  unauthenticated fallback if that service is unavailable.
- A revealed password hides after 15 seconds, on panel deactivation, or closing.
  Searches and group changes cancel pending authentication. Late results after
  closing/reopening cannot reveal a stale account.
- Copy clears the clipboard after 30 seconds only if nobody has changed it.
- Remove asks for confirmation. CSV import uses the existing browser-export
  parser on a background queue. It does not read another browser's store.

Storage:
- New writes use a generic-password Keychain vault scoped to the profile path,
  accessible while this device is unlocked. It is not iCloud synchronization or
  access to Apple's Passwords app. The current core still holds decrypted
  credentials in memory while Slate is running; panel rows retain metadata only.
- Old password files are read for compatibility. The first successful save puts
  the current set in Keychain. Old files are retained, not silently deleted.
- Keychain denial, malformed data and unsupported schema versions do not produce
  an empty replacement vault. The UI reports unavailable storage/save failures.
- The test target substitutes all Keychain operations; it does not access real
  Keychain items.

Autofill:
- The current app uses WebKit. Password queries use WebKit's main-frame security
  origin, not an origin supplied in a JavaScript message.
- Automatic matching is restricted to the same scheme, host and port. Bare
  imported domains default to HTTPS. No automatic parent/subdomain or www sharing.
- Only HTTPS main frames may use this bridge; private browsing remains excluded.
  The fill callback rechecks origin before calling page code after navigation.
- This is the existing first-account autofill flow, not a new multi-account
  suggestion picker.

Validation:
- App build succeeds and all 12 CTest tests pass. The existing audio test needs
  normal macOS codec access outside the restricted execution environment.
- Password-origin tests reject subdomains, host lookalikes, different schemes,
  non-default ports and userinfo URLs. Default HTTPS port normalization is tested.
- Mock Keychain tests cover round trips, profile separation, denied reads/writes,
  preservation on failure, malformed data and unsupported versions.
- A separate native preview with three synthetic in-memory accounts verified
  grouped accounts, search, masked rows and secure Add form through accessibility.
  No real credentials were imported, displayed or copied during these checks.
- Real Touch ID/passcode completion and its 15-second timer were not exercised.
  Screenshot capture produced a distorted thumbnail, so full visual review remains
  a manual check.

Not part of this pass: direct Chrome/Arc credential import, a passkey ceremony
bridge from Passkeys.swift, extension passkey coordination, or a new autofill
account picker. Existing passkey behavior is unchanged. The reference's native
passkey implementation requires its own origin, entitlement, cancellation and
WebAuthn compatibility review; it was not pasted into the password UI.
