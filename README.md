# Slate

**A native Mac browser built around the cost of keeping tabs open.**

Slate is for people who keep a large browsing workspace and move between a few active pages. Its central goal is to reduce the resources that workspace needs while keeping active work responsive and under the user's control.

The project centers on **tab lifecycle and resource use**: a saved tab can exist without a loaded page, a loaded page can survive workspace switches, and unloading is an explicit decision with clear consequences. The browser uses AppKit and the system WebKit engine on Apple Silicon, with browsing data stored locally.

## Why Slate exists

The workload that guides Slate is simple: keep 20–30 tabs available, work in a few, move between them quickly, and return to the others when needed. The questions that matter are how many pages must stay live, how much memory the whole browser uses, how quickly a page returns, and what state survives the transition.

Slate approaches that workload through three design choices:

- **Separate the tab list from loaded pages.** Saved tabs retain their identity, address, title, grouping, and Keep loaded preference. Restart restores the tab list and loads the selected workspace; other pages load when selected. Users can unload a page while retaining its tab.
- **Keep active pages intact while switching.** Moving between loaded tabs and split groups reuses their existing WebKit views. The tested switching path preserves edited forms and in-page state. PiP uses the existing page's media session, and its lifecycle is coordinated with the selected workspace.
- **Keep the browser shell small and local.** Slate uses native macOS UI and the system rendering engine, so it does not bundle a separate Chromium runtime. Browser state and content-blocking preferences are stored locally; saved passwords use macOS Keychain.

Split tabs, vertical tabs, spaces, and PiP are ways to use that foundation. The project should earn its place through resource use, page continuity, and predictable behavior in a small native application.

## What works today, and what still needs proof

The current implementation has separate logical and loaded tab states, lazy session restoration, confirmed manual unloading, Keep loaded controls, native memory-pressure observation, and reuse of live pages during workspace switches. Its C++ resource policy models protected tabs and proposed lifecycle transitions.

**Automatic tab unloading is disabled.** Visiting saved tabs increases the number of live pages; switching away does not unload them. The policy is not connected to automatic page destruction, and the WebKit adapter does not yet establish complete protection coverage for arbitrary page state. Manual unload warns that form entries, scrolling, playback, and page history may be lost; restoring an unloaded tab reloads its URL. Session persistence is not a snapshot of a running web application.

The first [whole-browser benchmark](docs/BENCHMARKS.md) measures the browser and its content, network, and graphics processes across three fresh-profile runs on an M3 Pro Mac with 18 GiB RAM:

| Controlled local workload | Slate footprint | Chrome footprint |
| --- | ---: | ---: |
| 24 pages loaded in both browsers | 1,194 MiB | 1,629 MiB |
| Slate restores 24 saved tabs with only one page loaded | 234 MiB | Not a matched comparison |

Figures are medians of run medians. Slate used about 27% less footprint in this specific loaded-page test, with substantial variation between runs. The same-origin synthetic pages and system memory pressure limit what it proves about everyday websites. The [report and raw measurements](docs/BENCHMARKS.md) include ranges, versions, workload details, exclusions, and reproduction steps. A small application bundle alone does not establish low runtime memory use.

The benchmark also passed 90 loaded split/single workspace checks with edited fields and JavaScript state preserved. Median synchronous native activation plus validation was 4.24 ms; this excludes later painting and display scanout. Unloaded tabs reload their URL and have a different latency and state-loss boundary.

The next milestones are:

1. Extend the initial benchmark to mixed sites, longer sessions, matched restore policies, and end-to-end visual latency.
2. Complete and test the protection contract for editing, media, capture, downloads, and uncertain page state before enabling automatic unloading.
3. Connect eligible lifecycle transitions to cancellable engine operations, then verify both resource savings and state preservation.

See [resource lifecycle and safety](docs/RESOURCE_SAFETY.md) for the current implementation boundary.

## Everyday browsing

Slate includes horizontal and vertical tabs, persistent split groups, spaces, native picture-in-picture, bookmarks, downloads, and local content blocking. The current source includes immediate presentation of loaded split groups, vertical split drag targets, and PiP exit handling that restores the selected pages.

## Build

Requirements: Apple Silicon Mac, Xcode command-line tools, CMake 3.21 or later, and Python 3. Node.js is optional for the JavaScript fixture tests.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 4
open build/platform/macos/Slate.app
```

No Chromium SDK is required. The signing script uses a local Apple Development identity when available and an ad-hoc signature otherwise. Certificates and provisioning profiles are not included.

## Tests

```sh
ctest --test-dir build --output-on-failure
```

The current macOS build registers 19 native tests in CMake, plus 4 JavaScript fixture tests when Node.js is installed (23 total). Native workspace regressions use a separate verification build:

```sh
cmake -S . -B build-verify -DCMAKE_BUILD_TYPE=Release -DSLATE_ENABLE_VERIFY=ON
cmake --build build-verify -j 4
python3 scripts/verify_split_switch.py --app build-verify/platform/macos/Slate.app
python3 scripts/verify_split_switch.py --app build-verify/platform/macos/Slate.app --followup
python3 scripts/verify_fullscreen_controls.py --app build-verify/platform/macos/Slate.app
```

The verification command runner is disabled by default. Regression runs use fresh temporary browser data and local fixture pages. The split/PiP checks passed locally; authenticated Max playback has not been verified, and integrated stream ads may still appear.

## Privacy and security

This repository contains application source, public filter lists, and synthetic test fixtures. It excludes personal browser data, cookies, saved passwords, API keys, signing certificates, local build artifacts, and historical development logs. Security features and their tests remain part of the application.

The browser stores personal browsing data locally at runtime. Keep local browser profiles and signing material outside Git. See [security architecture](docs/SECURITY.md), [password storage](docs/PASSWORDS.md), and [ad-block architecture](docs/ADBLOCK_MEDIA_ARCHITECTURE.md) for implementation details.

## Source layout

- `core/`: tabs, navigation, credentials, resources, and library models.
- `engine/`: WebKit integration, media monitoring, and content rules.
- `platform/macos/`: native browser UI and OS integrations.
- `filtering/`: filter engine and bundled lists, with attribution in `filtering/lists/NOTICE.txt`.
- `tests/`: unit tests and synthetic browser fixtures.
- `scripts/`: build, signing, and verification helpers.
- `docs/`: architecture and feature documentation.

## License

Original Slate source is available under the [MIT license](LICENSE). Bundled EasyList and EasyPrivacy filter data retain their separate terms in [filtering/lists/NOTICE.txt](filtering/lists/NOTICE.txt). The optional flower media fixtures are CC0, as noted in [tests/fixtures/README.md](tests/fixtures/README.md).
