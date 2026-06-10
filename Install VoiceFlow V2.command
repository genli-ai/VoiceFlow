#!/bin/bash
#
# VoiceFlow V2 安装脚本（Qwen3-ASR 引擎，MLX）
# 要求：macOS 15+、Apple Silicon、完整 Xcode（MLX 的 Metal 着色器需要 Xcode 编译）
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
bold "║   VoiceFlow V2 安装（Qwen3-ASR 引擎）      ║"
bold "╚══════════════════════════════════════════╝"

ARCH=$(uname -m)
OS_VER=$(sw_vers -productVersion)
echo "  系统：macOS ${OS_VER}（${ARCH}）"
[ "$ARCH" = "arm64" ] || fail "V2 需要 Apple Silicon。Intel 机型请使用 main 分支的 V1。"

# ── 1. 检查 Xcode 与 Metal 工具链 ───────────────────
step "1/4 检查 Xcode"
DEV_DIR=$(xcode-select -p 2>/dev/null || echo "")
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
    if [ -d "/Applications/Xcode.app" ]; then
        echo "  检测到 Xcode 但未设为默认工具链，需要你的开机密码切换："
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer || fail "切换失败"
        sudo xcodebuild -license accept 2>/dev/null || true
    else
        fail "未找到 /Applications/Xcode.app。请先从 App Store 安装 Xcode。"
    fi
fi
XCODE_VER=$(xcodebuild -version 2>/dev/null | head -1)
[ -n "$XCODE_VER" ] || fail "xcodebuild 不可用，请打开一次 Xcode 完成组件安装后重试"
green "  ✓ ${XCODE_VER}"

# Metal 工具链（Xcode 26 起默认不内置；必须实际执行检测——光查路径会被占位桩骗过）
if ! xcrun metal --version >/dev/null 2>&1; then
    echo "  Metal 编译工具链缺失，开始自动下载（一次性，约 2-4GB）…"
    xcodebuild -downloadComponent MetalToolchain \
        || fail "Metal 工具链下载失败。请手动运行：xcodebuild -downloadComponent MetalToolchain"
    xcrun metal --version >/dev/null 2>&1 \
        || fail "Metal 工具链仍不可用，请打开 Xcode → Settings → Components 手动安装后重试"
    green "  ✓ Metal 工具链就绪"
fi

# 分词器资源检查（模型仓库不带 tokenizer.json，App 运行时自动补进模型目录）
if [ ! -f "Resources/QwenTokenizer/tokenizer.json" ]; then
    red "  ⚠ 缺少 Resources/QwenTokenizer/tokenizer.json"
    fail "请先双击 scripts/Generate Qwen Tokenizer.command 生成分词器，再重新运行本脚本"
fi

# ── 2. 编译（xcodebuild） ───────────────────────────
step "2/4 编译 VoiceFlow V2（首次需拉取 MLX 依赖并编译 Metal 着色器，5-15 分钟）"
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

# ── 3. 打包 .app ───────────────────────────────────
step "3/4 打包应用"
STAGE=$(mktemp -d)
APP="$STAGE/VoiceFlow.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/VoiceFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# MLX/Tokenizer 等 SPM 资源包（含 Metal 着色器库），必须随 App 分发
if compgen -G "$PRODUCTS/*.bundle" > /dev/null; then
    for B in "$PRODUCTS"/*.bundle; do
        ditto "$B" "$APP/Contents/Resources/$(basename "$B")"
    done
    green "  ✓ 已嵌入 $(ls -d "$PRODUCTS"/*.bundle | wc -l | tr -d ' ') 个资源包"
fi

# Qwen 分词器资源
mkdir -p "$APP/Contents/Resources/QwenTokenizer"
cp "Resources/QwenTokenizer/tokenizer.json" "$APP/Contents/Resources/QwenTokenizer/"

# 图标
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

# 清理 + 签名
find "$APP" \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
xattr -rc "$APP" 2>/dev/null || true
codesign --force -s - "$APP" || fail "签名失败"
codesign --verify --deep "$APP" || fail "签名校验未通过"
green "  ✓ VoiceFlow.app (V2) 打包完成"

# ── 4. 安装 ─────────────────────────────────────────
step "4/4 安装到 /Applications"
pkill -x VoiceFlow 2>/dev/null || true
sleep 0.5
DEST="/Applications/VoiceFlow.app"
rm -rf "$DEST" 2>/dev/null
if ! ditto "$APP" "$DEST" 2>/dev/null; then
    DEST="$HOME/Applications/VoiceFlow.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$APP" "$DEST" || fail "无法复制到应用程序文件夹"
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
touch "$DEST" 2>/dev/null || true
tccutil reset Accessibility com.ligen.voiceflow >/dev/null 2>&1 || true
green "  ✓ 已安装：$DEST"

open "$DEST"

echo
bold "🎉 V2 安装完成！接下来："
echo
echo "  1. 重新授权【辅助功能】（系统设置 → 隐私与安全性 → 辅助功能，"
echo "     列表里已有就先删除再重新添加 $DEST）"
echo "  2. 首次使用：设置 → 识别 → 「下载模型」（约 860MB，一次性）"
echo "  3. 模型有更新时：设置 → 识别 → 「检查更新」一键对比远端版本"
echo
echo "按任意键关闭本窗口…"; read -n 1 -s || true
