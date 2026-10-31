# Disney+ playback with Shields enabled

The previous streaming helper intercepted `fetch`, `Response.json`, XHR response
getters, and `JSON.parse`. It deleted Disney playback `stream.insertion` and
source insertion fields and emptied `pods` / `ads` arrays. Those changes could
remove the timeline and source metadata that the player uses to coordinate
protected audio and video. Generic cosmetic guesses such as `docked-player`,
`floating-player`, and `ad-wrapper` could also hide a real player container.

This update:

- Leaves fetch, XHR request methods, and text/binary responses untouched on
  `disneyplus.com` and its subdomains. JSON.parse, Response.json, and native XHR
  JSON results filter only `ads.metadata`, `ads.document`, `ads.dxc`, `ads.live`,
  and `ads.vod`. Unknown ad fields, arrays, stream insertion, source insertion,
  pods, breaks, and DRM data remain intact. No fetch response is reconstructed,
  cloned, or pre-consumed. Native parse/reviver errors and Response rejections
  are retained; frozen results do not crash playback.
- Removes the unvalidated Disney insertion/pod rewriting.
- Excludes Disney documents from ambiguous generic player/container hiding.
- Keeps native network protection enabled. Explicit blocks for the bundled
  EasyPrivacy destinations `analytics.disneyplus.com`,
  `sanalytics.disneyplus.com`, and `beacons.digital.disneyadvertising.com` are
  applied after broad playback compatibility exceptions.
- Blocks the separate `ads.digital.disneyadvertising.com` delivery host. The
  existing lists covered its beacon host but omitted this ad-delivery endpoint.
- Does not change Disney's protected video playback speed or mute state merely
  because an ad badge is visible. Explicit, enabled Skip Ad controls can still
  be used. Encrypted videos on other supported players also retain their speed.
- Bumps the compiled-rule cache revision to V16 so the new cosmetic and
  network rules are rebuilt automatically.

Regression checks execute the injected script with synthetic Disney playback
responses through the browser APIs, including both audio/video source metadata,
actual ad-configuration removal, revivers, invalid JSON, frozen objects, text
responses, and rejected promises. They also check protected-video speed/audio safety, explicit ad
skip controls, tracker filtering, allowed playback requests, and successful
compilation of the complete native WebKit rule list.

These checks do not establish that every Disney+ ad is removed. Ads stitched
into an encrypted media stream cannot safely be removed by deleting response
metadata. Signed-in real-site playback must still be checked. After installing
the new build, restart Slate and reload the episode to discard scripts from the
old document. Clearing browsing data or signing out is not required by this fix.

Rule references (the helper is independently implemented):

- https://github.com/uBlockOrigin/uAssets/blob/master/filters/filters-2023.txt
  lists the five ad-configuration fields. Its broader stream insertion removal
  is deliberately excluded here because of the reported playback regression.
- https://github.com/uBlockOrigin/uAssets/blob/master/filters/unbreak.txt
  lists `ads.digital.disneyadvertising.com` separately from playback hosts.
