#!/bin/bash
# 打可分发包：通用二进制 + zip + dmg + SHA256SUMS，产物在仓库根目录 dist/
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DIST="$(cd .. && pwd)/dist"

UNIVERSAL=1 ./build.sh
rm -rf "$DIST" && mkdir -p "$DIST"

STAGE="$(mktemp -d)"
cp -R build/ClockClock.app "$STAGE/"
ditto -c -k --keepParent "$STAGE/ClockClock.app" "$DIST/ClockClock-$VERSION.zip"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "ClockClock" -srcfolder "$STAGE" -ov -format UDZO "$DIST/ClockClock-$VERSION.dmg"
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 "ClockClock-$VERSION.zip" "ClockClock-$VERSION.dmg" > SHA256SUMS.txt)

echo "dist:"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS.txt"
