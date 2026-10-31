# Passwords, Apple Passwords, and passkeys

The supplied Swift Apple Passwords protocol, helper connection, passkey relay,
and offer policy are adapted into `platform/macos/passwords/`. Slate's existing
Objective-C++ shell calls them through a generated Objective-C header. Its saved
password vault remains profile-specific and stored in Keychain; no existing
password file is replaced by this integration.

## Saved in Slate

Passwords has searchable site groups, expandable accounts, fixed ten-dot masks,
inline Add/Cancel/Save, File and browser import controls, and removal limited to
the current search. Show and Copy still require macOS verification. Revealed
secrets hide after 15 seconds, closing or deactivating the panel, or changing its
search. An unchanged clipboard clears after 30 seconds.

A native picker appears beneath recognized sign-in fields. It holds account IDs
and display names; passwords are retrieved only for the selected ID. Every fill
checks its document, frame, origin, focus token, private-tab state, and enabled
setting. Filling uses the input element's setter and input/change events.
Password-creation and one-time-code fields are excluded. The toolbar menu also
holds IDs instead of passwords, and revalidates its tab and origin on selection.

An unopened or locked Slate vault is not treated as empty. An existence-only
Keychain query explicitly prohibits authentication UI. If the vault may exist,
the picker offers **Unlock Slate passwords…**; only clicking it reads the vault.
This keeps the Apple offer from appearing ahead of an account Slate already has.

## Apple Passwords

Settings → Passwords has an optional switch, Connect, and a six-digit pairing
field. This is the supplied unofficial native-messaging integration with Apple's
Chrome extension helper, not a public Passwords app API. It requires macOS 15.4+
and a helper on one of the two system-volume paths, with the expected identifier
and an Apple-anchored code signature. The helper is checked again before launch.
There is no shell invocation and no protocol or secret log.

The helper starts only from a native Connect button or a click on the offer.
Turning the switch on alone does not start it. The paired session key is held
only in memory and discarded on disconnect, helper exit, disabling filling or
Apple Passwords, and application termination. A later launch needs pairing again.
Helper exits, timeouts, wrong codes, stale proofs, and messages from another
session fail closed. Only account names are requested until an account is picked.
Returned sites are checked again before filling. Apple-filled passwords are
recognized with a per-fill HMAC so they are not offered for saving in Slate.

The quiet **Use your Apple passwords?** row follows the supplied offer policy:

- HTTPS, ordinary tabs, and the page or a same-site HTTPS frame only.
- No offer ahead of any Slate account for that registrable site, including when
  the vault is still locked or unopened.
- At most once per registrable site, recorded only when actually displayed.
- Two unanswered displays retire it globally. Its × retires it immediately.
- Filling must be enabled, Apple Passwords off, and the signed helper available.
- Test builds never launch Apple's helper; policy tests use isolated defaults.

The system public-suffix lookup includes private suffixes such as github.io.
When unavailable, domain matching falls back to the exact host.

## Passkeys

The supplied WebAuthn bridge supports get/create, conditional account choices,
security keys, cancellation, credential serialization, and PRF outputs sealed to
a per-request page key. The native caller origin comes from WKFrameInfo; the page
cannot choose it. Requests are limited to the committed document and appropriate
site/frame, and pending operations are cancelled on navigation or close.

Apple's `com.apple.developer.web-browser.public-key-credential` entitlement is
required by these browser APIs. Slate checks the effective app signature rather
than a preference or plist claim. The present ad-hoc build does not have Apple's
approval, so the passkey setting is unavailable and ordinary password fallback
remains in place. Adding a requested entitlement to a file does not grant it.
After obtaining Apple's approval and appropriate provisioning, sign with the
approved entitlements through `SLATE_ENTITLEMENTS` / `SLATE_CODESIGN_IDENTITY`.

## Verification

CMake builds a separate stand-in-only password test executable. It never starts
the real helper or asks for real passwords, Touch ID, or passkeys. Checks cover
independent Python SRP vectors, AES-GCM authentication failures, offer persistence,
site/private-suffix rules, wrong-code and disconnect races, PRF sealing, JavaScript
field tokens and cancellation, and the native panel without opening a window.
The native Keychain persistence tests replace all Keychain entry points.

Run `cmake --build build -j 4` and `ctest --test-dir build --output-on-failure`.
The public-source vector generator is `scripts/generate-password-test-vectors.py`.
Live Apple helper pairing and entitled passkey ceremonies remain unverified.

Apple references:
- https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential
- https://support.apple.com/en-gb/guide/passwords/mchlf7ac261e/mac
