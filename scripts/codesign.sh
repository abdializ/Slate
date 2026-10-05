#!/bin/bash
# Sign Slate with a stable Apple Development identity so Chromium Keychain
# items survive relaunches. Does not disable the Chromium sandbox or use a
# mock keychain.
#
# Hardened-runtime entitlements are not attached here. This workspace lives
# under iCloud/File Provider Documents, which rewrites FinderInfo; launchd then
# refuses a hardened bundle (POSIX 163). The development identity still gives
# Keychain a stable designated requirement (identifier + team).
set -euo pipefail
export COPYFILE_DISABLE=1
APP="${1:?usage: codesign.sh Slate.app}"
IDENTITY="${SLATE_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1 || true)"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "Slate: no Apple Development identity; sealing the app with an ad-hoc signature."
  echo "Keychain access may prompt again until the app has a stable development signature."
  IDENTITY="-"
fi
TEAM_ID="$(security find-certificate -c "$IDENTITY" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null \
  | grep -oE 'OU[[:space:]]*=[[:space:]]*[A-Z0-9]{10}' \
  | head -1 \
  | awk -F= '{gsub(/ /,"",$2); print $2}' || true)"
if [[ -n "$TEAM_ID" ]]; then
  echo "Slate: using team ID $TEAM_ID"
fi

# File Provider on iCloud Documents re-applies FinderInfo while we sign in place.
# Stage a copy outside that tree, strip xattrs, sign, then copy the signature back.
STAGE="$(mktemp -d /tmp/slate-sign.XXXXXX)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT
ditto --norsrc --noextattr "$APP" "$STAGE/Slate.app"
xattr -cr "$STAGE/Slate.app" >/dev/null 2>&1 || true
FRAMEWORK="$STAGE/Slate.app/Contents/Frameworks/Chromium Embedded Framework.framework"
if [[ -L "$FRAMEWORK/Versions/A/A" ]]; then
  rm -f "$FRAMEWORK/Versions/A/A"
fi
sign() {
  local identifier="$1" path="$2"
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - --identifier "$identifier" "$path"
  else
    codesign --force --sign "$IDENTITY" --identifier "$identifier" \
     --options runtime --timestamp=none "$path"
  fi
}
if [[ -d "$FRAMEWORK" ]]; then
  sign org.chromium.framework "$FRAMEWORK"
fi
for helper in "$STAGE/Slate.app/Contents/Frameworks"/Slate\ Helper*.app; do
  if [[ -d "$helper" ]]; then
    name="$(basename "$helper" .app)"
    sign "dev.slate.browser.${name// /_}" "$helper"
  fi
done
ENTITLEMENTS="${SLATE_ENTITLEMENTS:-$(cd "$(dirname "$0")/.." && pwd)/platform/macos/Slate.entitlements}"
if [[ -f "$ENTITLEMENTS" && "$IDENTITY" != "-" ]]; then
  codesign --force --sign "$IDENTITY" --identifier "dev.slate.browser" \
   --options runtime --entitlements "$ENTITLEMENTS" --timestamp=none "$STAGE/Slate.app"
else
  sign "dev.slate.browser" "$STAGE/Slate.app"
fi
ditto --norsrc --noextattr "$STAGE/Slate.app" "$APP"
xattr -cr "$APP" >/dev/null 2>&1 || true
echo "Slate: signed with $IDENTITY"
