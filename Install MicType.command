#!/bin/bash
#
# MicType installer — build from source and install
# MicType 安装脚本——从源码编译并安装
# Requires: macOS 15+, Apple Silicon, full Xcode
#
set -u

cd "$(dirname "$0")/MicType" || { echo "MicType directory not found / 找不到 MicType 目录"; exit 1; }

# 双语输出：跟随系统语言
SYS_LANG=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p')
case "$SYS_LANG" in
    *zh*) ZH=1 ;;
    *)    ZH=0 ;;
esac
t() { if [ "$ZH" = "1" ]; then printf "%s" "$1"; else printf "%s" "$2"; fi; }

bold()  { printf "\033[1m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
step()  { echo; bold "==> $1"; }

fail() {
    echo
    red "✗ $1"
    echo
    echo "$(t "把上面的报错信息发给开发助手即可。按任意键退出…" "Send the error above to your dev assistant. Press any key to exit…")"
    read -n 1 -s || true
    exit 1
}

echo
bold "╔══════════════════════════════════════════╗"
bold "║   MicType $(t "安装" "Installer")                          ║"
bold "╚══════════════════════════════════════════╝"


ARCH=$(uname -m)
[ "$ARCH" = "arm64" ] || fail "$(t "需要 Apple Silicon" "Apple Silicon required")"

# ── 1. Xcode & Metal toolchain ─────────────────────
step "1/4 $(t "检查 Xcode" "Checking Xcode")"
DEV_DIR=$(xcode-select -p 2>/dev/null || echo "")
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
    if [ -d "/Applications/Xcode.app" ]; then
        echo "  $(t "切换默认工具链，需要开机密码：" "Switching default toolchain — your login password is required:")"
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer || fail "$(t "切换失败" "Switch failed")"
    else
        fail "$(t "未找到 /Applications/Xcode.app" "/Applications/Xcode.app not found")"
    fi
fi
xcodebuild -version >/dev/null 2>&1 || fail "$(t "xcodebuild 不可用" "xcodebuild unavailable")"
if ! xcrun metal --version >/dev/null 2>&1; then
    echo "  $(t "下载 Metal 工具链（一次性，约 2-4GB）…" "Downloading the Metal toolchain (one-time, ~2-4 GB)…")"
    xcodebuild -downloadComponent MetalToolchain || fail "$(t "Metal 工具链下载失败" "Metal toolchain download failed")"
fi
[ -f "Resources/QwenTokenizer/tokenizer.json" ] || fail "$(t "缺少分词器：先运行 scripts/Generate Qwen Tokenizer.command" "Tokenizer missing — run scripts/Generate Qwen Tokenizer.command first")"
green "  ✓ $(t "构建环境就绪" "Build environment ready")"

# ── 2. Build ───────────────────────────────────────
step "2/4 $(t "编译 MicType（首次 5-15 分钟）" "Building MicType (first build takes 5-15 min)")"
DERIVED=".xcbuild"
if xcodebuild -scheme MicType \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED" \
    build 2>&1 | tee build.log | grep -E "^(\\*\\* BUILD|error:)" ; then
    :
fi
PRODUCTS="$DERIVED/Build/Products/Release"
BIN="$PRODUCTS/MicType"
[ -f "$BIN" ] || fail "$(t "编译失败。请把 MicType/build.log 最后 50 行发给开发助手。" "Build failed. Send the last 50 lines of MicType/build.log to your dev assistant.")"
green "  ✓ $(t "编译成功" "Build succeeded")"

# ── 3. Package ─────────────────────────────────────
step "3/4 $(t "打包应用" "Packaging the app")"
STAGE=$(mktemp -d)
APP="$STAGE/MicType.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/MicType"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# MLX/tokenizer resource bundles (incl. Metal shaders) must ship with the app
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
codesign --force -s - "$APP" || fail "$(t "签名失败" "Code signing failed")"
codesign --verify --deep "$APP" || fail "$(t "签名校验未通过" "Signature verification failed")"
green "  ✓ $(t "打包完成" "Packaging complete")"

# ── 4. Install ─────────────────────────────────────
step "4/4 $(t "安装到 /Applications" "Installing to /Applications")"
pkill -x MicType 2>/dev/null || true
sleep 0.5
DEST="/Applications/MicType.app"
rm -rf "$DEST" 2>/dev/null
if ! ditto "$APP" "$DEST" 2>/dev/null; then
    DEST="$HOME/Applications/MicType.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$APP" "$DEST" || fail "$(t "无法复制到应用程序文件夹" "Could not copy to the Applications folder")"
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
touch "$DEST" 2>/dev/null || true
tccutil reset Accessibility com.ligen.mictype >/dev/null 2>&1 || true
green "  ✓ $(t "已安装：" "Installed: ")$DEST"

open "$DEST"

echo
bold "🎉 $(t "MicType 安装完成！接下来：" "MicType installed! Next steps:")"
echo
echo "  1. $(t "重新授权【辅助功能】：系统设置 → 隐私与安全性 → 辅助功能（已有条目先删再加）" "Re-grant Accessibility: System Settings → Privacy & Security → Accessibility (remove the old entry, then add again)")"
echo "  2. $(t "首次使用：设置 → 识别 → 下载模型（约 860MB，一次性）" "First run: Settings → Recognition → Download Model (~860 MB, one-time)")"
echo "  3. $(t "轻点右⌥听写；按住右⌥说指令（改写/回复/草拟/翻译）" "Tap Right-Option to dictate; hold it to speak commands (rewrite/reply/draft/translate)")"
echo
echo "$(t "按任意键关闭本窗口…" "Press any key to close…")"
read -n 1 -s || true
