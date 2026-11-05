#!/bin/bash
# 编译状态栏版 → build/ClockClock.app（ad-hoc 签名，无第三方依赖）
# UNIVERSAL=1 同时编 arm64 + x86_64，产出通用二进制
set -euo pipefail
cd "$(dirname "$0")"

WEB_PAGE="$(cd .. && pwd)/index.html"
APP="build/ClockClock.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
MIN_MACOS="13.0"

if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS="arm64 x86_64"; else ARCHS="$(uname -m)"; fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

TMPBIN="$(mktemp -d)"
BINS=()
for arch in $ARCHS; do
  out="$TMPBIN/ClockClock-$arch"
  swiftc -O -whole-module-optimization -target "${arch}-apple-macos${MIN_MACOS}" \
    -o "$out" main.swift -framework AppKit 2>&1 | grep -v "libswiftCompatibilityPacks" || true
  BINS+=("$out")
done
lipo -create -output "$APP/Contents/MacOS/ClockClock" "${BINS[@]}"
rm -rf "$TMPBIN"

sed "s|__WEB_PAGE__|$WEB_PAGE|" Info.plist > "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
echo "  version: $VERSION"
echo "  archs  : $(lipo -archs "$APP/Contents/MacOS/ClockClock")"
echo "  size   : $(du -h "$APP/Contents/MacOS/ClockClock" | cut -f1)"
