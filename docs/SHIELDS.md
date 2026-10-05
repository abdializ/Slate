# Slate Shields V0.1

Slate Shields is built into the browser. It is not an extension. Network
requests are classified locally against bundled EasyList and EasyPrivacy
network-rule extracts, then cancelled in CEF before the resource downloads.

## What V0.1 does

- One shared `ShieldController` / `FilterEngine` for every tab.
- EasyList + EasyPrivacy **network** rules, a small extra host list
  (`filtering/lists/slate-network.txt`), and media-compatibility exceptions
  (`filtering/lists/compat.txt`) so YouTube/Kick media CDNs are not blocked
  by host rules.
- CEF `OnBeforeResourceLoad` returns `RV_CANCEL` for blocked subresources.
  Main-frame documents, CSP reports, and downloads are never cancelled by
  Shields.
- Site pause and a global off switch. Standard and Strict use the same lists
  in V0.1; Strict does not add extra syntax or scriptlets.
- Compact shield control in the title bar and a native popover with the
  blocked-request count for the current page.

## What V0.1 does not do

- Cosmetic hiding, scriptlets, or arbitrary JavaScript injection.
- Remote classification. Typed search suggestions still go to Google, the
  same way Chrome does; visited page URLs are not sent to a filter service.
- A claim that YouTube or Kick advertisements are fully blocked. Those sites
  still fail live playback on this CEF build because of missing H.264/AAC,
  independent of Shields. See [MEDIA.md](MEDIA.md).
- Brave’s `adblock-rust` engine. That library is MPL-2.0 and is the intended
  replacement once a Rust toolchain is part of the build. The current matcher
  is original C++ that understands a subset of EasyList network syntax
  (`||`, `@@`, `$script`/`image`/…, `third-party`, `domain=`). Cosmetic,
  regex, redirect, and CSP rules are skipped at parse time.

## Performance targets

These are engineering budgets, not published product claims.

| Metric | Budget | V0.1 |
| --- | --- | --- |
| Incremental engine memory | &lt; 30 MB | Measure after loading both lists; expected tens of MB of rule strings, not a second copy per tab |
| Typical classify | &lt; 0.1 ms p95 | Host- and token-indexed lookup; Release unit tests: 400 classifies of a Google ad URL in 3.4 ms (~0.009 ms each) |
| Extra processes | none | Classification runs on CEF’s IO thread |
| Filter copies | one per profile | `ShieldController` is process-wide |

If measured engine memory exceeds 30 MB, keep the shared instance and record
the number rather than splitting lists per tab.

## Security

- HTTPS list files are bundled at build time; V0.1 does not download filter
  updates.
- EasyList/EasyPrivacy extracts remain GPLv3 data; see
  `filtering/lists/NOTICE.txt`.
- Sandbox, site isolation, and certificate checks stay on.
- Filter lists cannot run scriptlets.

## Files

```text
core/shields.h                 shared controller, site pause, page stats
filtering/network_engine.h     EasyList-syntax network matcher
engine/webkit_shields.mm       WKContentRuleList network shield compiler
platform/macos/main.mm         shield popover
filtering/lists/               bundled network extracts + compat exceptions
tests/shields_tests.cc
tests/fixtures/shields.html
```
