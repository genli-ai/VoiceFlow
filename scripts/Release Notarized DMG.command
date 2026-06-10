#!/bin/bash
#
# 构建 → Developer ID 签名 → 公证 → DMG（正式分发用）
# Build → sign with Developer ID → notarize → DMG (for public distribution)
#
# 使用前：填好下面三个变量（见 docs/发布工程-公证DMG指南.md 第 0 步）
set -u

# ════════ 必填配置 / REQUIRED ════════
TEAM_ID="YOUR_TEAM_ID"                       # developer.apple.com → Membership
APPLE_ID="ligen.thu@gmail.com"               # 你的 Apple ID
APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"           # appleid.apple.com 生成的 App 专用密码
# ═════════════════════════════════════

CERT="Developer ID Application"              # 证书名前缀，钥匙串中自动匹配
VERSION=$(plutil -extract CFBundleShortVersionString raw "$(dirname "$0")/../VoiceFlow/Resources/Info.plist")

cd "$(dirname "$0")/../VoiceFlow" || exit 1

fail() { echo; printf "\033[31m✗ %s\033[0m\n" "$1"; read -n 1 -s; exit 1; }
step() { echo; printf "\033[1m==> %s\033[0m\n" "$1"; }

[ "$TEAM_ID" != "YOUR_TEAM_ID" ] || fail "请先填写脚本顶部的 TEAM_ID / Fill in TEAM_ID first"

# ── 1. 编译 ─────────────────────────────────────────
step "1/5 编译 / Build"
xcodebuild -scheme VoiceFlow -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .xcbuild build 2>&1 | tee build.log | grep -E "^(\\*\\* BUILD|error:)" || true
PRODUCTS=".xcbuild/Build/Products/Release"
[ -f "$PRODUCTS/VoiceFlow" ] || fail "编译失败，见 build.log"

# ── 2. 打包 .app ────────────────────────────────────
step "2/5 打包 / Package"
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

# ── 3. Developer ID 签名（Hardened Runtime，公证必需） ──
step "3/5 签名 / Code-sign"
cat > "$STAGE/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
    <!-- 如果公证版启动后识别崩溃，解开下一行的注释重新运行 -->
    <!-- <key>com.apple.security.cs.allow-jit</key><true/> -->
</dict></plist>
PLIST
# 递归签所有嵌入的 bundle/dylib，再签主体
find "$APP/Contents/Resources" -name "*.bundle" -o -name "*.dylib" -o -name "*.metallib" 2>/dev/null | while read -r ITEM; do
    codesign --force --timestamp --options runtime -s "$CERT" "$ITEM" 2>/dev/null || true
done
codesign --force --deep --timestamp --options runtime \
    --entitlements "$STAGE/entitlements.plist" \
    -s "$CERT" "$APP" || fail "签名失败——确认钥匙串里有 Developer ID Application 证书"
codesign --verify --deep --strict "$APP" || fail "签名校验失败"

# ── 4. 生成 DMG ─────────────────────────────────────
step "4/5 生成 DMG / Create DMG"
mkdir -p ../release
DMG="../release/VoiceFlow-${VERSION}.dmg"
rm -f "$DMG"
DMGDIR=$(mktemp -d)
ditto "$APP" "$DMGDIR/VoiceFlow.app"
ln -s /Applications "$DMGDIR/Applications"
hdiutil create -volname "VoiceFlow" -srcfolder "$DMGDIR" -ov -format UDZO "$DMG" || fail "DMG 生成失败"
codesign --force --timestamp -s "$CERT" "$DMG"

# ── 5. 公证 + 装订 ──────────────────────────────────
step "5/5 公证（通常 2-10 分钟）/ Notarize"
xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" \
    --wait || fail "公证失败——用 xcrun notarytool log <submission-id> 查看原因"
xcrun stapler staple "$DMG" || fail "装订失败"

echo
printf "\033[32m✅ 完成：%s\033[0m\n" "$(cd ../release && pwd)/VoiceFlow-${VERSION}.dmg"
echo "上传到 GitHub Releases 即可分发。按任意键关闭…"
read -n 1 -s || true
