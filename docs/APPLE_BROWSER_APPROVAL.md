# Apple browser entitlement approval for Slate

The entitlement is `com.apple.developer.web-browser.public-key-credential`.
Apple grants it through a managed capability. A local signing certificate and
an entry in an entitlements file do not grant approval.

## Who applies

Apple requires the Account Holder of an **organization's Apple Developer
account** for this entitlement. A personal or free development signing identity
is not sufficient for this request.

## Request

1. Sign in as the organization's Account Holder.
2. Register or select Slate's explicit App ID: `dev.slate.browser`.
3. Submit [macOS Browsers Passkeys](https://developer.apple.com/contact/request/macos-browsers-passkeys/).
4. Describe Slate as a general-purpose native macOS browser using system WebKit,
   with a URL field, search, tabs, and bookmarks. Request passkeys/security keys
   for arbitrary websites using the browser AuthenticationServices APIs.
5. Provide a reviewable build and repository when requested:
   [Slate](https://github.com/abdializ/Slate). Approval and timing are Apple's
   decision; the request itself does not enable the capability.

Slate already declares HTTP and HTTPS URL schemes and presents a URL field and
search. Those match the basic browser criteria in Apple's entitlement page.

## After approval

Enable the approved managed capability for the App ID in Certificates,
Identifiers & Profiles, or add it through Xcode. Generate the appropriate new
provisioning profile and sign a build with the approved team and entitlement.
A public distribution build also needs suitable distribution signing and the
managed provisioning profile packaged correctly. Verify the effective signed
entitlements and profile before testing or distributing it. Do not reuse another
browser's identifier or signing identity.

Slate's build supports selecting its signing identity and entitlements through
`SLATE_CODESIGN_IDENTITY` and `SLATE_ENTITLEMENTS`. The approved provisioning
profile must also be integrated into that distribution build. The current
ad-hoc build intentionally does not claim this entitlement.

Then test real passkey requests and Apple Passwords pairing on the target Mac.
The Passwords helper protocol is unofficial; approval alone does not establish
that every helper version or pairing operation works.

## Why Connect was silent

The helper installed on this development Mac has a signed parent launch
constraint admitting the browser entitlement or named browser identities. The
unapproved launch was terminated before its initial capabilities reply. Slate
now detects the known restriction on recent macOS, explains it inline, and
avoids offering an unavailable connection. The separate Combine UI refresh bug
that hid pairing progress/code entry has also been corrected.

References:

- [Entitlement requirements](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
- [Managed capability requests](https://developer.apple.com/help/account/capabilities/capability-requests)
