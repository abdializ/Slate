# Slate 0.4.20

- **Fix Cloudflare "Verify you are human" (Turnstile) compatibility:**
  - Replaced Chrome 130 User-Agent spoofing with WebKit's genuine macOS Safari User-Agent (`config.applicationNameForUserAgent` matched to the Mac's installed Safari version) so TLS/JA4, HTTP/2, JavaScriptCore, and User-Agent are 100% consistent across all pages, Turnstile iframes, and Web Workers.
  - Removed detectable prototype tampering (`Function.prototype.toString` hooking, fake `navigator.deviceMemory`, own-property `navigator` overrides, and live canvas mutation) from Incognito stealth scripts and exempted verification challenge iframes (`challenges.cloudflare.com`, `hcaptcha.com`, `recaptcha.net`) from script overrides and content blocking.
