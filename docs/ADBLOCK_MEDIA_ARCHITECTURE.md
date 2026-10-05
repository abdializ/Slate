# Ad blocking and media audit

## Before this change

- `WebKitShields` already compiled a shared `WKContentRuleList` from bundled EasyList/EasyPrivacy extracts and reused WebKit's persistent compiled-list store. Its parser only handled a small domain-rule subset and accepted some modifiers too broadly. A single 20,000-rule cap could exhaust itself on EasyList before reaching EasyPrivacy.
- Each web view also received a cosmetic script and a streaming-ad script. The latter hooked `fetch`, `JSON.parse`, and XHR, and polled media every second. The global switch detached the native list, but these scripts remained active. The per-site switch paused only `ShieldController`; the native list still blocked that site.
- The WebKit configuration allowed audiovisual autoplay without a gesture. Its media bridge scanned every element and every shadow root once per second. Tab switches and window occlusion floated any playing video, including unsolicited autoplay. The browser's manual float moved the existing `WKWebView` into a panel and polled for replacement videos four times per second.

## Current behavior

- Native WebKit rules handle network and cosmetic filtering. A strict converter accepts supported domain/resource modifiers, deduplicates rules, skips unsupported syntax, and logs counts. EasyList and EasyPrivacy each receive a 20,000-native-rule budget. Specific cosmetic selectors compile as `css-display-none`. The compiled list's cache key hashes the source file contents. Slate no longer builds a second in-memory filter engine at startup. No GPL converter source was copied or linked.
- Streaming sites also receive the in-player ad handler at navigation commit. It handles ad metadata, clicks explicit ad-skip controls, and mutes and accelerates detected finite ad playback, then restores the original sound and speed when the ad signal ends. Twitch live playback is muted during a detected ad but is not accelerated. It is injected only for exact streaming domains and their subdomains when both blocker switches permit it, rather than running on every page. This restores first-party streaming coverage that network rules alone cannot provide.
- The global and site switches persist locally. Both detach or reattach the native list on the affected web views; site changes reload the current page once. Private windows share these explicit preferences. A site's `www` host maps to the same site choice. Other subdomains retain their own policy rather than being collapsed incorrectly.
- WebKit requires a user gesture for audiovisual content with audio. Muted inline autoplay remains available. The small media bridge listens to actual media and trusted input events; it has no polling. It considers only visible, reasonably sized, user-started videos for automatic PiP. It scores candidates and targets one frame. Native WebKit PiP is requested on tab switch or app deactivation; automatic PiP returns inline when the user returns to its origin. A manual exit suppresses automatic reopening until the next user-started media session.
- The existing manual float panel is retained. Its video replacement handling uses a scoped mutation observer and play events instead of a timer. It rejects hidden, tiny, and obvious ad videos.
- The shield popover reports policy state, not a fabricated blocked-request count. Public `WKContentRuleList` APIs do not provide per-request block events. Developer verification commands expose current policy and media state.

## Remaining limits

- Bundled lists are used; background downloads and scheduled list updates are not implemented. A new build with changed bundled files invalidates the compiled-list cache. A failed compile keeps the previous in-memory list for that run.
- The native converter intentionally skips unsupported ABP syntax. It does not implement general regex, scriptlets, redirects, or all domain modifiers.
- Registrable-domain matching requires a public-suffix implementation. Current site choices normalize `www` only, to avoid applying a choice to unrelated subdomains.
- The manual browser float is still a `WKWebView` panel; automatic PiP uses the page's native WebKit media element. Real-site verification remains necessary for YouTube, Twitch, news sites, OAuth popups, and app-focus transitions.

## References

- [Apple WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore)
- [Apple mediaTypesRequiringUserActionForPlayback](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/mediatypesrequiringuseractionforplayback)
- [AdGuard SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) (architecture reference, GPLv3)
- [SafariAdBlock](https://github.com/coldnuclearfusion/SafariAdBlock)
- [AdGuard Mini for macOS](https://github.com/AdguardTeam/AdGuardMiniForMac)
