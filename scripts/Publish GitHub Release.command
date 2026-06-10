#!/bin/bash
#
# 发布 GitHub Release：构建 → 打包 zip 到 release/ → 打 tag → gh 创建 Release
# Publish a GitHub release: build → zip into release/ → tag → create via gh CLI
#
set -u
cd "$(dirname "$0")/.." || exit 1

SYS_LANG=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p')
case "$SYS_LANG" in *zh*) ZH=1 ;; *) ZH=0 ;; esac
t() { if [ "$ZH" = "1" ]; then printf "%s" "$1"; else printf "%s" "$2"; fi; }
fail() { echo; printf "\033[31m✗ %s\033[0m\n" "$1"; read -n 1 -s; exit 1; }
step() { echo; printf "\033[1m==> %s\033[0m\n" "$1"; }

VERSION=$(plutil -extract CFBundleShortVersionString raw VoiceFlow/Resources/Info.plist)
TAG="v${VERSION}"
ZIP="release/VoiceFlow-${VERSION}-arm64.zip"
NOTES="docs/release-notes-v${VERSION}.md"

command -v gh >/dev/null 2>&1 || fail "$(t "未安装 GitHub CLI。安装：brew install gh，然后 gh auth login" "GitHub CLI not found. Install: brew install gh, then gh auth login")"
gh auth status >/dev/null 2>&1 || fail "$(t "gh 未登录，先运行：gh auth login" "gh not authenticated — run: gh auth login")"
[ -f "$NOTES" ] || fail "$(t "缺少发布说明：" "Release notes missing: ")$NOTES"

# ── 1. 构建并打包 ───────────────────────────────────
step "1/3 $(t "构建并打包" "Build & package") ${TAG}"
cd VoiceFlow || exit 1
xcodebuild -scheme VoiceFlow -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .xcbuild build 2>&1 | tee build.log | grep -E "^(\\*\\* BUILD|error:)" || true
PRODUCTS=".xcbuild/Build/Products/Release"
[ -f "$PRODUCTS/VoiceFlow" ] || fail "$(t "编译失败，见 VoiceFlow/build.log" "Build failed — see VoiceFlow/build.log")"

STAGE=$(mktemp -d)
APP="$STAGE/VoiceFlow.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/VoiceFlow" "$APP/Contents/MacOS/VoiceFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for B in "$PRODUCTS"/*.bundle; do
    [ -e "$B" ] && ditto "$B" "$APP/Contents/Resources/$(basename "$B")"
done
mkdir -p "$APP/Contents/Resources/QwenTokenizer"
cp Resources/QwenTokenizer/tokenizer.json "$APP/Contents/Resources/QwenTokenizer/"
if [ -f "Resources/AppIcon.png" ]; then
    ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
    for SZ in 16 32 128 256 512; do
        sips -z $SZ $SZ Resources/AppIcon.png --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null
        sips -z $((SZ*2)) $((SZ*2)) Resources/AppIcon.png --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi
find "$APP" \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
xattr -rc "$APP" 2>/dev/null || true
codesign --force -s - "$APP" || fail "$(t "签名失败" "Code signing failed")"
cd ..
mkdir -p release
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP" || fail "$(t "打包 zip 失败" "Zip packaging failed")"
echo "  ✓ $ZIP ($(du -h "$ZIP" | cut -f1))"

# ── 2. 打 tag 并推送 ────────────────────────────────
step "2/3 $(t "打标签并推送" "Tag & push") ${TAG}"
git tag "$TAG" 2>/dev/null || echo "  $(t "标签已存在，跳过" "Tag exists, skipping")"
git push origin main --tags || fail "$(t "推送失败" "Push failed")"

# ── 3. 创建 Release ─────────────────────────────────
step "3/3 $(t "创建 GitHub Release" "Create GitHub release")"
if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP" --clobber || fail "$(t "上传资产失败" "Asset upload failed")"
    echo "  $(t "Release 已存在，已更新资产" "Release exists — asset updated")"
else
    gh release create "$TAG" "$ZIP" \
        --title "VoiceFlow ${VERSION}" \
        --notes-file "$NOTES" --latest || fail "$(t "创建 Release 失败" "Release creation failed")"
fi

echo
printf "\033[32m✅ %s\033[0m\n" "$(t "发布完成！" "Published!") $(gh release view "$TAG" --json url -q .url 2>/dev/null)"
echo "$(t "按任意键关闭…" "Press any key to close…")"; read -n 1 -s || true
