#!/bin/bash
# 打可分发包（只出 dmg）：通用版 + Apple Silicon 专版，加 SHA256SUMS
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DIST="$(cd .. && pwd)/dist"
rm -rf "$DIST" && mkdir -p "$DIST"

dmg_for() {                        # $1 基名  $2 构建出来的 .app
  local base="$1" app="$2" tmp
  tmp="$(mktemp -d)"
  cp -R "$app" "$tmp/ClockClock.app"
  ln -s /Applications "$tmp/Applications"
  hdiutil create -quiet -volname "ClockClock" -srcfolder "$tmp" -ov -format UDZO "$DIST/$base.dmg"
  rm -rf "$tmp"
}

echo "== 通用版（arm64 + x86_64）"
ARCHS="arm64 x86_64" OUT="build/ClockClock-universal.app" ./build.sh
dmg_for "ClockClock-$VERSION" "build/ClockClock-universal.app"

echo "== Apple Silicon 专版（arm64）"
ARCHS="arm64" OUT="build/ClockClock-arm64.app" ./build.sh
dmg_for "ClockClock-$VERSION-arm64" "build/ClockClock-arm64.app"

(cd "$DIST" && shasum -a 256 ./*.dmg > SHA256SUMS.txt)

echo
echo "dist:"
ls -lh "$DIST"
echo
cat "$DIST/SHA256SUMS.txt"
