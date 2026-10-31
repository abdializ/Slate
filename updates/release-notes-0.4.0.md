# Slate 0.4.0

- Redesign the omnibox to match the supplied reference: a 560 × 50 field, 14-point corners, neutral light/dark colors, quiet selection, a subtle breathing shadow, and a separate dropdown eight points below it.
- Keep the field still as suggestions arrive. Fit the field to narrow panes and keep long addresses editable with horizontal scrolling.
- Suggest bookmarks first, retain useful visited pages, and place the selected search engine's search last. Complete addresses inline without making Backspace put deleted letters back.
- Keep pointer hover separate from keyboard selection. Arrow keys can leave the list; Tab accepts site search, and Tab or Right Arrow accepts an address ending.
- Add ⌘K to find open tabs by name or address, in recent-use order. Repeating ⌘K cycles through them; releasing Command after cycling takes the selected tab.
- Add optional whole-address commands in Settings → Search, including settings, history, downloads, bookmarks, passwords, and new private tab. Commands stay off until enabled.
- Add local per-space browsing history, a History window, and memory-only blank-tab drafts. Private visits are not saved. Hide URL usernames and passwords while editing.
- Support ⌘Return to open the destination in a background tab and ⇧⌘Return to open it in the foreground from the center field.
- Follow Reduce Motion and offer lighter motion for low-power or thermally limited Macs.

Restart Slate after updating. Use ⌘L for the omnibox and ⌘K for open tabs.
