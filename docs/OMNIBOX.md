# Omnibox reference integration

This version adapts `AllOmniboxFeatures.swift` to Slate's existing AppKit shell.
The combined reference is not a build unit. Shared site matching and anonymous
engine suggestions remain in the search module from 0.3.0. `Omnibox.swift` adds
the reference's command aliases, place ranking, completion and keyboard walking;
`omnibox_overlay.mm` supplies native AddressField, SiteChip, row, Breath and
floating-field counterparts.

The field is 560 × 50 at most, with 14-point corners, 22-point horizontal padding,
15.5-point type and 22-point content height. It sits 30 points above the pane's
center and narrows to the pane minus 28 points. A separate non-activating panel
keeps the field's frame unchanged as results change. Its six-point inset, 34-point
rows and neutral colors follow the reference. Inline fields use a 320–460-point
panel, clamped to the visible screen, with overflow scrolling. Hover is local to
the row; only keyboard walking changes the selected result.

Completion uses actual history, bookmarks and built-in destinations. A single
letter can complete only a visited site's front door. Re-parsing must preserve
the destination's identity; public HTTP, paths, ports and fragments are retained.
The offered suffix is selected using NSString/UTF-16 offsets, IME composition is
left alone, and deletion suppresses re-completion for that edit. Option-Backspace
removes an offered suffix and the last typed word. A focus request made before
the view reaches its window is retried after arrival. Blank-tab drafts are held
in memory, scoped by space and tab, and removed on tab closure.

The ordinary field reserves three place rows, with bookmarks before history,
and appends a search when the input is not an address. The visited front door is
reserved when bookmarks would fill the list. Duplicate destinations get one row.
Only ⌘K lists other open tabs; it filters private status and sorts by recent use.
The picker never requests remote suggestions. Ordinary remote answers retain
eligible prefixes between requests and do not replace a keyboard-selected engine
result. They always remain searches, even if the returned words resemble a URL.

Address commands are disabled by default and require an exact alias. Their
native actions open the corresponding Slate UI. History can also be reached from
Navigate → History. Ordinary HTTP(S) visits are stored locally, at most 2,000 per
space, with credentials removed. Private visits are excluded before any history
read or write. Clearing history cancels pending writes and forgets learned sites.
Imported history is suggested only in the space where the import occurred.

Breath is a repeating Core Animation shadow, not a main-thread timer. The page
cover fades without scaling; the field alone arrives at 0.97 scale. Reduce Motion
removes shake and transitions; light-motion preference uses a brief transition
and suppresses breathing when low power or serious thermal limits apply. The
start page's previous greeting timer is stopped.

`search_services` checks ranking, deduplication, command opt-in/exact matching,
profile/private history, completion safety and keyboard walking alongside the
existing search checks. `omnibox_components` exercises the actual AppKit text
editor (Backspace, suffix acceptance, UTF-16 caret offsets, chip removal and
window-arrival focus), separate hover/selection, scrolling order, fixed geometry
and narrow panes. It renders the real controls in light and dark offscreen
windows without activating the user's browser. The full existing suite is kept.
