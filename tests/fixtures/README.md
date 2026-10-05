# Manual tab lifecycle smoke test

Start a loopback-only test page from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory tests/fixtures
```

Launch Slate with an absolute, separate test data directory to keep normal
browser data intact:

```sh
SLATE_DATA_DIR="$PWD/build/smoke-profile" build/platform/macos/Release/Slate.app/Contents/MacOS/Slate
```

Launch Services also works, and keeps stderr when redirected:

```sh
PROFILE="$PWD/build/smoke-profile"
open -n --env "SLATE_DATA_DIR=$PROFILE" --stderr "$PROFILE/slate.stderr.log" \
  build/platform/macos/Release/Slate.app
```

For an isolated-profile command script (must live inside `SLATE_DATA_DIR`;
ignored otherwise), set `SLATE_COMMAND_FILE` to that path. Supported lines:
`sleep N`, `select ID`, `unload`, `confirm`, `restore`, `vertical`, `newtab`, `reload`, `go URL`, `shieldsoff`, `shieldson`, `playmuted`, `quit`. `unload` still
shows the state-loss sheet; `confirm` presses Unload on that sheet. This is
not automatic discarding.

1. Create 20 tabs with ⌘T, navigating each to `http://127.0.0.1:8765/?tab=N`.
2. Quit and reopen with the same test directory. Confirm 20 sidebar records and
   exactly one loaded tab, then select two more tabs and confirm three loaded.
3. Enable Keep loaded. Verify Unload tab is disabled. Disable Keep loaded.
4. Unload a tab, confirm the state-loss prompt, and verify its record remains
   while the loaded count falls. Restore it; verify its URL reloads.
5. Type in the fixture input to arm beforeunload. Close or unload the tab, choose
   Stay, and verify it remains usable. Retry and choose Leave; verify close.
6. Quit while an edited page is loaded. Stay must cancel quit. Retry and Leave;
   the final log must contain SLATE_SHUTDOWN_COMPLETE and the process must exit.
7. Stop the fixture server with Ctrl+C when finished.

Review any system prompt yourself. Do not disable sandboxing, change
Keychain access rules or enter passwords into terminal commands to run this test.

This fixture sets beforeunload after input, exercising normal
user-activation requirements. The app saves URL/title, not input or history.

## Protection observations & Media Fixtures

The fixture directory also contains `static.html`, `form.html`, `media.html`,
`dynamic.html`, `frame.html`, `codecs.html`, `mse.html`, `hls.html`,
`pip_test.html`, and `shields.html` (plus `tone.wav`). Optional CC0 `flower.mp4` / `flower.webm`
samples sit beside them for codec, MSE, and Picture-in-Picture verification. Open them in separate tabs. After load and a probe,
hover a tab to see its protection reason:

- Static: No blocker observed, until document interaction is recorded.
- Form: Form or editable content, without needing to type anything.
- Media: Audio or video content, even without playback.
- PiP Active: Protected from discard under memory pressure while in Picture-in-Picture.
- Dynamic and frame: Page state uncertain.

Reload/navigation resets document-specific interaction history; unload and
restore accepts reports from the new renderer. Polling runs every 10
seconds; reports older than 30 seconds become unknown. Real system memory
pressure appears in the status bar. Unit tests exercise Warning/Critical/Unknown
policy inputs without putting the user's machine under artificial memory load.
Camera and microphone permissions must not be granted just to run these tests.
