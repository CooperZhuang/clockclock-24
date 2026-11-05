#!/bin/bash
# 公证（notarize）+ staple：把 ad-hoc 包变成别人点开就能跑的包
#
# 需要 Apple Developer Program（99 美元/年）签发的 Developer ID Application 证书。
# 凭据二选一：
#   A) app 专用密码：AC_USERNAME / AC_PASSWORD / AC_TEAM_ID
#   B) App Store Connect API 密钥：AC_KEY_PATH(.p8) / AC_KEY_ID / AC_ISSUER_ID
# 另外必须设置 CODESIGN_ID="Developer ID Application: 名字 (TEAMID)"
#
# 用法：CODESIGN_ID=... AC_USERNAME=... ./notarize.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DIST="$(cd .. && pwd)/dist"

: "${CODESIGN_ID:?请设置 CODESIGN_ID=\"Developer ID Application: 你的名字 (TEAMID)\"}"

AUTH=(--wait)
if [ -n "${AC_KEY_PATH:-}" ]; then
  AUTH+=(--key "$AC_KEY_PATH" --key-id "$AC_KEY_ID" --issuer "$AC_ISSUER_ID")
else
  : "${AC_USERNAME:?需要 AC_USERNAME（或改用 API 密钥）}"
  : "${AC_PASSWORD:?需要 AC_PASSWORD（app 专用密码）}"
  AUTH+=(--apple-id "$AC_USERNAME" --password "$AC_PASSWORD" --team-id "${AC_TEAM_ID:-}")
fi

echo "== 1/3 公证两个 .app 并 staple（离线也能过 Gatekeeper）"
for app in build/ClockClock-universal.app build/ClockClock-arm64.app; do
  [ -d "$app" ] || continue
  codesign --force --options runtime --timestamp --sign "$CODESIGN_ID" "$app"
  zip="$(mktemp -d)/$(basename "$app").zip"
  ditto -c -k --keepParent "$app" "$zip"
  echo "-- submit $(basename "$app")"
  xcrun notarytool submit "$zip" "${AUTH[@]}"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  rm -rf "$(dirname "$zip")"
done

echo "== 2/3 用已 staple 的 .app 重打 dmg（会重算 SHA256SUMS）"
SKIP_BUILD=1 CODESIGN_ID="$CODESIGN_ID" ./package.sh

echo "== 3/3 公证 dmg 并 staple"
for dmg in "$DIST"/ClockClock-"$VERSION".dmg "$DIST"/ClockClock-"$VERSION"-arm64.dmg; do
  [ -f "$dmg" ] || continue
  codesign --force --timestamp --sign "$CODESIGN_ID" "$dmg"
  echo "-- submit $(basename "$dmg")"
  xcrun notarytool submit "$dmg" "${AUTH[@]}"
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  echo "-- Gatekeeper 检查"
  spctl -a -vvv -t open --context context:primary-signature "$dmg" || true
done

(cd "$DIST" && shasum -a 256 ./*.dmg > SHA256SUMS.txt)
echo "公证完成：$DIST"
