#!/bin/bash
#
# Build local ZIP/DMG artifacts for the latest installed VoiceFlow app.
# It keeps only the newest package files in ./release and removes old root-level artifacts.
#
set -euo pipefail

cd "$(dirname "$0")/.."

ROOT_DIR="$(pwd)"
RELEASE_DIR="$ROOT_DIR/release"
APP_PATH="${1:-/Applications/VoiceFlow.app}"

if [ ! -d "$APP_PATH" ] && [ -d "$HOME/Applications/VoiceFlow.app" ]; then
    APP_PATH="$HOME/Applications/VoiceFlow.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "找不到 VoiceFlow.app。请先安装，或把 .app 路径作为参数传入："
    echo "  scripts/Package Latest Release.command /path/to/VoiceFlow.app"
    exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
    VERSION="$(date +%Y%m%d%H%M)"
fi

ARCH="$(uname -m)"
ZIP_PATH="$RELEASE_DIR/VoiceFlow-v${VERSION}-${ARCH}.zip"
DMG_PATH="$RELEASE_DIR/VoiceFlow-v${VERSION}-${ARCH}.dmg"

mkdir -p "$RELEASE_DIR"

find "$RELEASE_DIR" -maxdepth 1 -type f \( -name 'VoiceFlow-v*.zip' -o -name 'VoiceFlow-v*.dmg' \) -delete
find "$ROOT_DIR" -maxdepth 1 -type f \( -name 'VoiceFlow-v*.zip' -o -name 'VoiceFlow-v*.dmg' \) -delete

echo "打包来源：$APP_PATH"
echo "输出目录：$RELEASE_DIR"
echo

echo "生成 ZIP..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "生成 DMG..."
hdiutil create \
    -volname "VoiceFlow ${VERSION}" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo
echo "完成。当前 release 目录只保留："
ls -lh "$RELEASE_DIR"
