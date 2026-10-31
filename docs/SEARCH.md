# Search integration

Slate's search components are adapted from the supplied `AllSearchFeatures.swift`
reference. The combined reference stays outside the build. Its separate Address,
Engine, EngineSuggest, SiteSearch, Keyword and PageFind components live under
`platform/macos/search`. The native AppKit shell supplies the fields, site chip,
settings and Find controls instead of the reference app's SwiftUI Browser types.

Search settings are in Settings → Search. Suggestions are off by default and
always suppressed in private tabs and while a site chip is selected. The
suggestion transport uses an ephemeral session, no cookies, credentials, cache or
referrer, no redirects, a 120 ms debounce, an 800 ms resource timeout, and a 64 KB
response limit. Only the selected engine receives eligible search words. Tests
use a local fake engine; production does not read a test endpoint override.

Site search includes the reference's 16 built-in destinations. Tab activates the
matching site's chip; clicking the site row also activates it. Backspace from an
empty chip field, its ×, or Escape removes it. Keyword shortcuts continue working
when site suggestions are disabled. Learned OpenSearch descriptions require a
visited HTTPS page and same-site HTTPS redirects, use no browser cookies or
credentials, and are streamed with a 64 KB cap. Templates keep a fixed destination
and place one `%s` in a path, query or fragment. Learned sites are named by host,
limited to 40 per space, excluded from private tabs and other spaces, and can be
forgotten from Search settings. Visit ranking is capped at 2,000 hosts per space.
The system suffix boundary is shared in approach with Slate's password policy;
if it is unavailable, same-site checks require an exact host.

Find uses an isolated WebKit content world and script arguments instead of source
interpolation. It reads visible text, same-origin frames and eligible form
controls without replacing page nodes. Matching supports case, whole words,
Unicode normalization, incremental counts, mutation updates and stale-generation
rejection. It restores the original selection when possible. PDFKit retains PDF
search with a case option; whole-word mode is unavailable for PDFs. Return and
Shift-Return navigate; Escape closes. Narrow fields keep keyboard navigation.

The Swift bridge targets macOS 12, matching Slate. Newer URL and sleep APIs from
the supplied reference were adapted to this deployment target. Explicit typed
regular files have a one-use main-frame allowance in the navigation policy;
remote pages cannot set that allowance. Merely requesting suggestions never
checks local file existence.

Validation: `search_services` tests address resolution, encoding, templates,
keywords, site matching/profile isolation, suggestion privacy, cancellation,
redirects and timeouts against a local server, plus PageFind in real offscreen
WebKit pages. `search_components` checks the actual AppKit chip and responsive
Find controls and renders Search settings. Neither test activates a browser
window. Existing browser tests remain part of the full suite.
