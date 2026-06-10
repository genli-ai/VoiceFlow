#!/bin/bash
#
# VoiceFlow V2 安装脚本（Qwen3-ASR + Whisper 双引擎）
# 要求：macOS 15+、Apple Silicon、完整 Xcode（MLX 的 Metal 着色器需要 Xcode 编译）
#
set -u

cd "$(dirname "$0")/VoiceFlow" || { echo "找不到 VoiceFlow 目录"; exit 1; }

WHISPER_VERSION="v1.8.4"
XCF_NAME="whisper-${WHISPER_VERSION}-xcframework.zip"
XCF_DIRECT="https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_VERSION}/${XCF_NAME}"

bold()  { printf "\033[1m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
step()  { echo; bold "==> $1"; }

fail() {
    echo
    red "✗ $1"
    echo
    echo "把上面的报错信息发给 Claude 即可。按任意键退出…"; read -n 1 -s || true
    exit 1
}

download() {
    local dest="$1"; shift
    for url in "$@"; do
        echo "  尝试：$url"
        if curl -fL --connect-timeout 20 --retry 2 -C - -o "${dest}.part" "$url"; then
            mv "${dest}.part" "$dest"
            return 0
        fi
        echo "  （此源失败，换下一个）"
    done
    return 1
}

echo
bold "╔══════════════════════════════════════════╗"
bold "║   VoiceFlow V2 安装（Qwen3-ASR 双引擎）    ║"
bold "╚══════════════════════════════════════════╝"

ARCH=$(uname -m)
OS_VER=$(sw_vers -productVersion)
echo "  系统：macOS ${OS_VER}（${ARCH}）"
[ "$ARCH" = "arm64" ] || fail "V2 需要 Apple Silicon。Intel 机型请使用 main 分支的 V1。"

# ── 1. 检查 Xcode ───────────────────────────────────
step "1/6 检查 Xcode（MLX 引擎需要完整 Xcode 编译）"
DEV_DIR=$(xcode-select -p 2>/dev/null || echo "")
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
    if [ -d "/Applications/Xcode.app" ]; then
        echo "  检测到 Xcode 但未设为默认工具链，需要你的开机密码切换："
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer || fail "切换失败"
        sudo xcodebuild -license accept 2>/dev/null || true
    else
        fail "未找到 /Applications/Xcode.app。请先从 App Store 安装 Xcode（搜索 Xcode → 获取）。"
    fi
fi
XCODE_VER=$(xcodebuild -version 2>/dev/null | head -1)
[ -n "$XCODE_VER" ] || fail "xcodebuild 不可用，请打开一次 Xcode 完成组件安装后重试"
green "  ✓ ${XCODE_VER}"

# Metal 工具链（Xcode 26 起默认不内置，需单独下载一次，约 2-4GB）
# 注意：必须实际执行 metal 来检测——新 Xcode 自带一个"占位桩"，光查路径会误判已安装
if ! xcrun metal --version >/dev/null 2>&1; then
    echo "  Metal 编译工具链缺失，开始自动下载（一次性，约 2-4GB，取决于网速）…"
    xcodebuild -downloadComponent MetalToolchain \
        || fail "Metal 工具链下载失败。请手动在终端运行：xcodebuild -downloadComponent MetalToolchain"
    xcrun metal --version >/dev/null 2>&1 \
        || fail "Metal 工具链仍不可用，请打开 Xcode → Settings → Components 手动安装 Metal Toolchain 后重试"
    green "  ✓ Metal 工具链就绪"
fi

# ── 2. whisper 框架（备用引擎） ──────────────────────
step "2/6 准备 whisper.cpp 引擎"
if [ -d "Frameworks/whisper.xcframework" ]; then
    green "  ✓ 已存在，跳过下载"
else
    mkdir -p Frameworks
    TMP_ZIP="Frameworks/${XCF_NAME}"
    download "$TMP_ZIP" \
        "$XCF_DIRECT" \
        "https://ghfast.top/${XCF_DIRECT}" \
        "https://gh-proxy.com/${XCF_DIRECT}" \
        || fail "whisper 框架下载失败（约 46MB）"
    TMP_DIR=$(mktemp -d)
    unzip -q "$TMP_ZIP" -d "$TMP_DIR" || fail "解压失败"
    FOUND=$(find "$TMP_DIR" -maxdepth 3 -type d -name "whisper.xcframework" | head -1)
    [ -n "$FOUND" ] || fail "压缩包里没有 whisper.xcframework"
    ditto "$FOUND" "Frameworks/whisper.xcframework"
    rm -rf "$TMP_DIR" "$TMP_ZIP"
    green "  ✓ whisper.xcframework 就绪"
fi

# ── 3. 编译（xcodebuild） ───────────────────────────
step "3/6 编译 VoiceFlow V2（首次需拉取 MLX 依赖并编译 Metal 着色器，5-15 分钟，请耐心）"
DERIVED=".xcbuild"
if xcodebuild -scheme VoiceFlow \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED" \
    build 2>&1 | tee build.log | grep -E "^(\\*\\* BUILD|error:|warning: Metal)" ; then
    :
fi
PRODUCTS="$DERIVED/Build/Products/Release"
BIN="$PRODUCTS/VoiceFlow"
[ -f "$BIN" ] || fail "编译失败。请把 VoiceFlow/build.log 最后 50 行发给 Claude。"
green "  ✓ 编译成功"

# ── 4. 打包 .app ───────────────────────────────────
step "4/6 打包应用"
STAGE=$(mktemp -d)
APP="$STAGE/VoiceFlow.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN" "$APP/Contents/MacOS/VoiceFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# MLX/Tokenizer 等 SPM 资源包（含 Metal 着色器库），必须随 App 分发
if compgen -G "$PRODUCTS/*.bundle" > /dev/null; then
    for B in "$PRODUCTS"/*.bundle; do
        ditto "$B" "$APP/Contents/Resources/$(basename "$B")"
    done
    green "  ✓ 已嵌入 $(ls -d "$PRODUCTS"/*.bundle | wc -l | tr -d ' ') 个资源包"
fi

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

# whisper 动态框架
SLICE=$(find Frameworks/whisper.xcframework -maxdepth 1 -type d -name "macos-*" | head -1)
[ -n "$SLICE" ] || fail "whisper.xcframework 里没有 macOS 架构"
ditto "$SLICE/whisper.framework" "$APP/Contents/Frameworks/whisper.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/VoiceFlow" 2>/dev/null || true

# 清理 + 签名
find "$APP" \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
xattr -rc "$APP" 2>/dev/null || true
codesign --force -s - "$APP/Contents/Frameworks/whisper.framework" || fail "框架签名失败"
codesign --force -s - "$APP" || fail "签名失败"
codesign --verify --deep "$APP" || fail "签名校验未通过"
green "  ✓ VoiceFlow.app (V2) 打包完成"

# ── 5. whisper 模型（备用引擎用，已有则跳过） ─────────
step "5/6 检查 whisper 备用模型"
MODELS_DIR="$HOME/Library/Application Support/VoiceFlow/models"
mkdir -p "$MODELS_DIR"
MODEL="ggml-large-v3-turbo-q5_0.bin"
if [ -f "$MODELS_DIR/$MODEL" ]; then
    green "  ✓ whisper 模型已存在"
else
    echo "  （可选）下载 whisper 备用模型，Qwen 模型装好后可不用它"
    download "$MODELS_DIR/$MODEL" \
        "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/$MODEL" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL" \
        || red "  whisper 模型下载失败——不影响 V2，可稍后在设置里补"
fi

# ── 6. 安装 ─────────────────────────────────────────
step "6/6 安装到 /Applications"
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
echo "  2. 打开 设置 → 识别 → 点「下载 Qwen 模型」（约 550MB，一次性）"
echo "  3. 下载完成后引擎默认「自动」即优先使用 Qwen3-ASR"
echo "  4. 悬浮窗耗时提示可对比新旧引擎的速度和准确率"
echo
echo "按任意键关闭本窗口…"; read -n 1 -s || true
