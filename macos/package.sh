#!/bin/bash
# 打可分发包：通用版 + Apple Silicon 专版，各出 zip/dmg，加 SHA256SUMS
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DIST="$(cd .. && pwd)/dist"
rm -rf "$DIST" && mkdir -p "$DIST"

stage_and_pack() {                 # $1 基名  $2 构建出来的 .app
  local base="$1" app="$2" tmp
  tmp="$(mktemp -d)"
  cp -R "$app" "$tmp/ClockClock.app"
  ditto -c -k --keepParent "$tmp/ClockClock.app" "$DIST/$base.zip"
  ln -s /Applications "$tmp/Applications"
  hdiutil create -quiet -volname "ClockClock" -srcfolder "$tmp" -ov -format UDZO "$DIST/$base.dmg"
  rm -rf "$tmp"
}

echo "== 通用版（arm64 + x86_64）"
ARCHS="arm64 x86_64" OUT="build/ClockClock-universal.app" ./build.sh
stage_and_pack "ClockClock-$VERSION" "build/ClockClock-universal.app"

echo "== Apple Silicon 专版（arm64）"
ARCHS="arm64" OUT="build/ClockClock-arm64.app" ./build.sh
stage_and_pack "ClockClock-$VERSION-arm64" "build/ClockClock-arm64.app"

(cd "$DIST" && shasum -a 256 ./*.zip ./*.dmg > SHA256SUMS.txt)

echo
echo "dist:"
ls -lh "$DIST"
echo
cat "$DIST/SHA256SUMS.txt"
