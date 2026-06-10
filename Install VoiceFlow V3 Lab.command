#!/bin/bash
#
# VoiceFlow V3 Lab 安装脚本（实验版，与正式版 VoiceFlow.app 并存）
# 要求：macOS 15+、Apple Silicon、完整 Xcode
#
set -u

cd "$(dirname "$0")/VoiceFlow" || { echo "找不到 VoiceFlow 目录"; exit 1; }

bold()  { printf "\033[1m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
step()  { echo; bold "==> $1"; }

fail() {
    echo
    red "✗ $1"
    echo
    echo "把上面的报错信息发给开发助手即可。按任意键退出…"; read -n 1 -s || true
    exit 1
}

echo
bold "╔══════════════════════════════════════════╗"
bold "║   VoiceFlow V3 Lab 安装（实验版）          ║"
bold "╚══════════════════════════════════════════╝"
echo "  与正式版 VoiceFlow.app 并存，设置/Key 相互独立，模型共享。"

ARCH=$(uname -m)
[ "$ARCH" = "arm64" ] || fail "需要 Apple Silicon"

# ── 1. 检查 Xcode 与 Metal 工具链 ───────────────────
step "1/4 检查 Xcode"
DEV_DIR=$(xcode-select -p 2>/dev/null || echo "")
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
    if [ -d "/Applications/Xcode.app" ]; then
        echo "  切换默认工具链，需要开机密码："
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer || fail "切换失败"
    else
        fail "未找到 /Applications/Xcode.app"
    fi
fi
xcodebuild -version >/dev/null 2>&1 || fail "xcodebuild 不可用"
if ! xcrun metal --version >/dev/null 2>&1; then
    echo "  下载 Metal 工具链（一次性，约 2-4GB）…"
    xcodebuild -downloadComponent MetalToolchain || fail "Metal 工具链下载失败"
fi
[ -f "Resources/QwenTokenizer/tokenizer.json" ] || fail "缺少分词器：先运行 scripts/Generate Qwen Tokenizer.command"
green "  ✓ 构建环境就绪"

# ── 2. 编译 ─────────────────────────────────────────
step "2/4 编译 VoiceFlow V3 Lab"
DERIVED=".xcbuild"
if xcodebuild -scheme VoiceFlow \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED" \
    build 2>&1 | tee build.log | grep -E "^(\\*\\* BUILD|error:)" ; then
    :
fi
PRODUCTS="$DERIVED/Build/Products/Release"
BIN="$PRODUCTS/VoiceFlow"
[ -f "$BIN" ] || fail "编译失败。请把 VoiceFlow/build.log 最后 50 行发给开发助手。"
green "  ✓ 编译成功"

# ── 3. 打包 ─────────────────────────────────────────
step "3/4 打包应用"
STAGE=$(mktemp -d)
APP="$STAGE/VoiceFlow V3 Lab.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/VoiceFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if compgen -G "$PRODUCTS/*.bundle" > /dev/null; then
    for B in "$PRODUCTS"/*.bundle; do
        ditto "$B" "$APP/Contents/Resources/$(basename "$B")"
    done
fi
mkdir -p "$APP/Contents/Resources/QwenTokenizer"
cp "Resources/QwenTokenizer/tokenizer.json" "$APP/Contents/Resources/QwenTokenizer/"

if [ -f "Resources/AppIcon.png" ]; then
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    for SZ in 16 32 128 256 512; do
        sips -z $SZ $SZ Resources/AppIcon.png --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null
        DBL=$((SZ * 2))
        sips -z $DBL $DBL Resources/AppIcon.png --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

find "$APP" \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
xattr -rc "$APP" 2>/dev/null || true
codesign --force -s - "$APP" || fail "签名失败"
codesign --verify --deep "$APP" || fail "签名校验未通过"
green "  ✓ 打包完成"

# ── 4. 安装（不动正式版 VoiceFlow.app） ──────────────
step "4/4 安装到 /Applications"
pkill -f "VoiceFlow V3 Lab.app" 2>/dev/null || true
sleep 0.5
DEST="/Applications/VoiceFlow V3 Lab.app"
rm -rf "$DEST" 2>/dev/null
if ! ditto "$APP" "$DEST" 2>/dev/null; then
    DEST="$HOME/Applications/VoiceFlow V3 Lab.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$APP" "$DEST" || fail "无法复制到应用程序文件夹"
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
touch "$DEST" 2>/dev/null || true
tccutil reset Accessibility com.ligen.voiceflow.v3 >/dev/null 2>&1 || true
green "  ✓ 已安装：$DEST"

open "$DEST"

echo
bold "🧪 V3 Lab 安装完成！注意："
echo
echo "  1. V3 Lab 是独立 App：需要单独授权麦克风和辅助功能（com.ligen.voiceflow.v3）"
echo "  2. 设置和 API Key 与正式版隔离——首次使用要在 V3 Lab 设置里重新填 Key"
echo "  3. 识别模型与正式版共享，不用重新下载"
echo "  4. 同时跑两个版本时注意快捷键会撞车——测试 V3 时建议先退出正式版"
echo
echo "按任意键关闭本窗口…"; read -n 1 -s || true
