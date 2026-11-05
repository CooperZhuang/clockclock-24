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
if [ -n "${CODESIGN_ID:-}" ]; then
  ./notarize.sh          # 有开发者证书时：签名 + 公证 + staple
fi

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

  # ---- 同步 Homebrew tap（版本号 + 通用版 dmg 的 sha256）----
  TAP_DIR="${CLOCKCLOCK_TAP:-$HOME/Documents/Code/Personal/homebrew-tap}"
  if [ -d "$TAP_DIR/.git" ]; then
    SUM="$(shasum -a 256 "../dist/ClockClock-$VERSION.dmg" | cut -d' ' -f1)"
    python3 - "$TAP_DIR/Casks/clockclock.rb" "$VERSION" "$SUM" <<'TAPPATCH'
import re, sys
path, ver, sha = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
s = re.sub(r'version "[^"]*"', f'version "{ver}"', s, count=1)
s = re.sub(r'sha256 "[^"]*"', f'sha256 "{sha}"', s, count=1)
open(path, "w").write(s)
print("tap cask ->", ver)
TAPPATCH
    (cd "$TAP_DIR" && git add -A && git commit -q -m "cask: clockclock $VERSION" && git push -q origin main && echo "tap 已推送") || true
  fi
fi

# ---- 本地更新（每次发版都做；必须在 Release / cask 都推完之后）----
INSTALL="/Applications/ClockClock.app"
if HOMEBREW_NO_AUTO_UPDATE=1 brew list --cask clockclock >/dev/null 2>&1; then
  echo "== 本机是 brew 装的，走 brew 升级"
  ( cd "$(brew --repo CooperZhuang/tap)" && git pull -q ) || true
  HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --cask clockclock \
    || HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall --cask clockclock
  echo "本地已更新：${INSTALL}（v${VERSION}，brew 管理）"
else
  pkill -f "ClockClock.app/Contents/MacOS/ClockClock" >/dev/null 2>&1 || true
  sleep 0.6
  rm -rf "$INSTALL"
  cp -R "build/ClockClock-universal.app" "$INSTALL"
  xattr -dr com.apple.quarantine "$INSTALL" >/dev/null 2>&1 || true
  open "$INSTALL"
  echo "本地已更新：${INSTALL}（v${VERSION}）"
fi
