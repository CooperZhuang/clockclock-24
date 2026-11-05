#!/bin/bash
# 发版：编译出 dmg → 本地替换 /Applications/ClockClock.app 并重启 →
#       （加 --publish）提交、打 tag、推、建 GitHub Release
#
# 用法: ./release.sh [发行说明.md] [--publish]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
NOTES=""
PUBLISH=""
for a in "$@"; do
  case "$a" in
    --publish) PUBLISH="--publish" ;;
    *) NOTES="$a" ;;
  esac
done

./package.sh

# ---- 本地更新（每次发版都做）----
INSTALL="/Applications/ClockClock.app"
pkill -f "ClockClock.app/Contents/MacOS/ClockClock" >/dev/null 2>&1 || true
sleep 0.6
rm -rf "$INSTALL"
cp -R "build/ClockClock-universal.app" "$INSTALL"
xattr -dr com.apple.quarantine "$INSTALL" >/dev/null 2>&1 || true
open "$INSTALL"
echo "本地已更新：${INSTALL}（v${VERSION}）"

# ---- 发布 ----
if [ "$PUBLISH" = "--publish" ]; then
  if [ -z "$NOTES" ] || [ ! -f "$NOTES" ]; then
    echo "缺发行说明文件：./release.sh notes.md --publish" >&2
    exit 1
  fi
  git add -A
  git commit -m "release: v$VERSION" || true
  git tag -a "v$VERSION" -m "ClockClock $VERSION" 2>/dev/null || true
  git push origin main --tags
  gh release create "v$VERSION" \
    "../dist/ClockClock-$VERSION.dmg" \
    "../dist/ClockClock-$VERSION-arm64.dmg" \
    "../dist/SHA256SUMS.txt" \
    --title "ClockClock $VERSION" --notes-file "$NOTES"
fi
