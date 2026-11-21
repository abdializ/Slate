# Slate 0.4.12

- Fix clicking an account in the inline Slate Vault autofill popover not filling the form or switching focus back to an open Passwords window (`acceptsFirstMouse` + immediate `mouseDown:` trigger + explicit browser window key-focus restoration before filling).
- Enable same-site matching and automatic vault unlock for the omnibox Autofill button (`⇧⌘L`).

Restart Slate after updating.
