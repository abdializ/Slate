# Slate

Slate is a native macOS browser built with AppKit and Apple WebKit. It supports horizontal and vertical tabs, persistent split groups, native picture-in-picture, spaces, bookmarks, downloads, and local content blocking.

This source snapshot includes instant switching between loaded split groups, vertical split drag targets, and PiP lifecycle handling that restores the selected workspace when a video player exits PiP. Ad iframe updates are aggregated separately from native PiP state.

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

The current macOS build has 21 tests when Node.js is installed. Native workspace regressions use a separate verification build:

```sh
cmake -S . -B build-verify -DCMAKE_BUILD_TYPE=Release -DSLATE_ENABLE_VERIFY=ON
cmake --build build-verify -j 4
python3 scripts/verify_split_switch.py --app build-verify/platform/macos/Slate.app
python3 scripts/verify_split_switch.py --app build-verify/platform/macos/Slate.app --followup
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
