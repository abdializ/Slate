# Slate 0.4.10

- Fix inline password autofill recognizing sites across subdomains (e.g. `www.linkedin.com` ↔ `linkedin.com`, `accounts.google.com` ↔ `google.com`) using registrable same-site matching, prioritizing exact host matches first.
- Support two-step sign-in pages (email/username step before password appears) and Single-Page App URL query/hash changes.
- Fix focus-loss race when clicking an account inside the autofill popover so selecting a saved login reliably fills both username and password immediately.

Restart Slate after updating.
