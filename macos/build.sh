#!/bin/bash
# 编译状态栏版：产出 build/ClockClock.app（ad-hoc 签名，无第三方依赖）
set -euo pipefail
cd "$(dirname "$0")"

WEB_PAGE="$(cd .. && pwd)/index.html"
APP="build/ClockClock.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -whole-module-optimization -o "$APP/Contents/MacOS/ClockClock" main.swift \
  -framework AppKit

sed "s|__WEB_PAGE__|$WEB_PAGE|" Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
echo "  binary : $(du -h "$APP/Contents/MacOS/ClockClock" | cut -f1)"
echo "  web    : $WEB_PAGE"
