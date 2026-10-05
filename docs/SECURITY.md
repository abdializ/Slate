# Security Architecture & Posture

Slate is a lightweight, personal macOS browser built with Apple WebKit (`WKWebView`), AppKit, and native Swift/Objective-C++.

The security architecture is built directly on top of Apple's system WebKit process isolation and macOS App Sandbox without heavyweight third-party engines or cloud dependencies.

---

## 1. Process Isolation & App Sandbox

- **macOS App Sandbox (`com.apple.security.app-sandbox`)**:
  The application runs fully sandboxed under macOS App Sandbox. Capabilities are granted using the principle of least privilege:
  - `com.apple.security.network.client`: Outgoing HTTPS/HTTP network connections for web browsing.
  - `com.apple.security.files.user-selected.read-write`: User-authorized file access through standard macOS open/save dialogs.
  - `com.apple.security.files.downloads.read-write`: Storage in `~/Downloads` for user downloads.
  - `com.apple.security.device.camera` & `com.apple.security.device.microphone`: Media capture hardware access only after explicit per-origin user approval.
  - `com.apple.security.print`: System printing pipeline.
  - **Insecure Entitlements Excluded**: `allow-jit` (main process), `allow-unsigned-executable-memory`, and `disable-library-validation` are strictly disabled.
- **WebKit Process Isolation**:
  Web content renders inside Apple's dedicated `com.apple.WebKit.WebContent` and `com.apple.WebKit.Networking` sandboxed XPC services. The browser UI process never parses untrusted DOM or executes website JavaScript directly.

---

## 2. Navigation, TLS, & Fraud Protection

- **HTTPS-First Address Resolution**:
  Bare domain queries (e.g. `bank.com`) automatically resolve to `https://bank.com`. Local development (`localhost`, `127.0.0.1`) remains supported on HTTP.
- **Scheme Enforcement**:
  Address bar input strictly rejects dangerous and non-navigational schemes (`javascript:`, `data:`, `file:`, `vbscript:`, `blob:`).
- **Navigation Policy & External Schemes**:
  - Remote web content cannot navigate to local `file://` resources.
  - Dangerous schemes (`javascript:`, `applescript:`, `terminal:`, `vbscript:`, `diskcopy:`) are blocked.
  - External communication schemes (`mailto:`, `tel:`) require explicit user interaction (`WKNavigationTypeLinkActivated`) and launch via `NSWorkspace`.
  - Arbitrary unknown external schemes from web pages are blocked.
- **TLS Certificate Validation**:
  WebKit's native TLS certificate verification is enforced. No custom challenge handlers bypass untrusted, self-signed, or expired certificates. Failed secure connections never silently downgrade to plain HTTP.
- **Native Phishing & Fraud Warning**:
  `WKPreferences.fraudulentWebsiteWarningEnabled` is enabled natively, leveraging Apple's local fraud protection without transmitting browsing history to third-party cloud services.
- **Pop-under & Spam Prevention**:
  `javaScriptCanOpenWindowsAutomatically` is set to `NO`. Only user-initiated popups are permitted.

---

## 3. JavaScript-to-Native Communication Security

- **Content World Isolation (`WKContentWorld.defaultClientWorld`)**:
  Internal scripts (Autofill, media status observers) and native script message handlers (`slateAutofill`, `slateMedia`) execute exclusively within isolated client worlds on macOS 11+.
- **Credential Protection & Passive Leak Mitigation**:
  Untrusted web scripts running in the page world cannot access, hook, or tamper with `slateAutofill` or `window.__slateAutofillCredentials`. Stored passwords are kept in isolated closure memory in `defaultClientWorld` and are never populated into the DOM `input[type="password"]` property until the user physically interacts with the form (`event.isTrusted === true`) or submits, preventing passive scraping by malicious third-party scripts.
- **Frame & Origin Verification**:
  Autofill requests are restricted to the top-level main frame (`forMainFrameOnly: YES`) and require origin verification against the active HTTPS website. Third-party iframes cannot invoke autofill.

---

## 4. Website Permissions

- **Explicit User Authorization**:
  Camera and microphone permissions (`requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:`) use `WKPermissionDecisionPrompt`, invoking WebKit's native permission modal per origin. Sensitive hardware is never granted silently.
- **No Cross-Origin Permission Inheritance**:
  Permissions are scoped strictly to the requesting origin.

---

## 5. Downloads & Gatekeeper Protections

- **Path Traversal Protection**:
  Download filenames are sanitized via `[filename lastPathComponent]`, stripping directory traversal (`../`), leading slashes, path separators, and dotfile prefixes. Resolved file destinations are strictly validated against the target downloads directory.
- **Gatekeeper Quarantine (`com.apple.quarantine`)**:
  All files downloaded via `WKDownload` and `NSURLSession` are tagged with quarantine metadata (`0081;...;dev.slate.browser;...`) and `LSFileQuarantineEnabled` is active in `Info.plist`. Downloaded binaries cannot execute without explicit user approval.
- **No Automatic Execution**:
  Downloaded executables or scripts are never automatically opened or executed.

---

## 6. Storage & Private Browsing

- **Saved Passwords in macOS Keychain**:
  Credentials are encrypted in the macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Plaintext passwords are never written to disk or logged to console/debug outputs.
- **Non-Persistent Private Browsing**:
  Private tabs use `[WKWebsiteDataStore nonPersistentDataStore]`. Browsing history, cookies, and cache from private sessions are never written to disk or the standard profile.
- **Storage Purge on Close**:
  When the last private tab is closed, `slate::PurgeIncognitoStorage()` wipes any remaining volatile session memory.
- **Local-Only Data**:
  Bookmarks, spaces, and session state are persisted strictly locally (`~/Library/Application Support/Slate`). No telemetry or remote sync services are present.
