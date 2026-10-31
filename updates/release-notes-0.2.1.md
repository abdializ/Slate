# Slate 0.2.1

- Browse saved passwords by site, add accounts inline, and remove only the accounts matching the current search.
- Choose saved accounts beneath sign-in fields, with document, focus, frame, and origin checks before filling.
- Optionally connect Apple Passwords using its signed system helper and a six-digit pairing code. The connection stays off until requested.
- Offer Apple Passwords sparingly: once per site, never ahead of an existing Slate account, and retire after two unanswered offers or a dismissal.
- Keep Apple-filled passwords out of Slate's save prompts and preserve existing Keychain vaults.
- Integrate the supplied passkey bridge, gated on Apple's approved browser signing entitlement. Passkeys are unavailable in the current ad-hoc build.

Live Apple helper pairing and entitled passkey ceremonies remain unverified.
