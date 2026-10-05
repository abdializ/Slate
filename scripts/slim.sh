#!/bin/bash
# Remove unused legacy CEF SDK and leftover local probe profiles.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Drop legacy CEF third_party folder completely (WebKit uses macOS system frameworks)
rm -rf "$ROOT/third_party"

if [[ -d "$ROOT/build" ]]; then
  shopt -s nullglob
  # Drop old CEF build wrappers, profile directories, and test caches
  rm -rf "$ROOT"/build/libcef_dll_wrapper "$ROOT"/build/*-profile* "$ROOT"/build/live-verify-* "$ROOT"/build/audio-probe-* "$ROOT"/build/media-* "$ROOT"/build/test_*
  # Clean old Release bundle if it contains stale CEF framework
  if [[ -d "$ROOT/build/platform/macos/Release/Slate.app/Contents/Frameworks" ]]; then
    rm -rf "$ROOT/build/platform/macos/Release"
  fi
fi

echo "=== Slate Workspace Size ==="
du -sh "$ROOT" 2>/dev/null || true
if [[ -d "$ROOT/build/platform/macos/Slate.app" ]]; then
  echo "=== Slate.app Bundle Size ==="
  du -sh "$ROOT/build/platform/macos/Slate.app"
fi

