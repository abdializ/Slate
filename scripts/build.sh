#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CMAKE="${CMAKE:-cmake}"
"$CMAKE" -S "$ROOT" -B "$ROOT/build" -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Release
"$CMAKE" --build "$ROOT/build" --parallel 4
"$CMAKE" --build "$ROOT/build" --target test
printf 'App: %s/build/platform/macos/Release/Slate.app\n' "$ROOT"
