#!/bin/bash
#
# VoiceFlow 一键安装脚本
# 双击运行：编译 → 打包 → 下载识别模型 → 安装到 /Applications
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
    echo "如果需要帮助，把上面的报错信息（和 VoiceFlow/build.log）发给 Claude 即可。"
    echo "按任意键退出…"; read -n 1 -s || true
    exit 1
}

download() {
    # download <目标文件> <url1> <url2> ...
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
bold "╔══════════════════════════════════════╗"
bold "║      VoiceFlow 语音输入法 安装        ║"
bold "╚══════════════════════════════════════╝"

ARCH=$(uname -m)
OS_VER=$(sw_vers -productVersion)
echo "  系统：macOS ${OS_VER}（${ARCH}）"

case "$OS_VER" in
    10.*|11.*|12.*|13.0*|13.1*|13.2*)
        fail "需要 macOS 13.3 或更高版本（当前 ${OS_VER}）" ;;
esac

# ── 1. 检查编译工具 ─────────────────────────────────
step "1/6 检查 Xcode 命令行工具"
if ! xcode-select -p >/dev/null 2>&1; then
    echo "  未安装。即将弹出 Apple 官方安装窗口（约 5 分钟）。"
    xcode-select --install 2>/dev/null || true
    echo
    bold "  请在弹出的窗口中点「安装」，装完后【重新双击本脚本】。"
    echo "  按任意键退出…"; read -n 1 -s || true
    exit 0
fi
if ! swift --version >/dev/null 2>&1; then
    fail "swift 命令不可用。请先完成 Xcode 命令行工具安装后重试。"
fi
green "  ✓ $(swift --version 2>/dev/null | head -1)"

# ── 2. 下载 whisper 预编译框架 ──────────────────────
step "2/6 准备 whisper.cpp 引擎（预编译，含 Metal 加速）"
if [ -d "Frameworks/whisper.xcframework" ]; then
    green "  ✓ 已存在，跳过下载"
else
    mkdir -p Frameworks
    TMP_ZIP="Frameworks/${XCF_NAME}"
    download "$TMP_ZIP" \
        "$XCF_DIRECT" \
        "https://ghfast.top/${XCF_DIRECT}" \
        "https://gh-proxy.com/${XCF_DIRECT}" \
        || fail "whisper 框架下载失败（约 46MB）。请检查网络后重试；或手动下载 ${XCF_DIRECT} 放到 VoiceFlow/Frameworks/ 下再运行。"
    TMP_DIR=$(mktemp -d)
    unzip -q "$TMP_ZIP" -d "$TMP_DIR" || fail "解压失败"
    FOUND=$(find "$TMP_DIR" -maxdepth 3 -type d -name "whisper.xcframework" | head -1)
    [ -n "$FOUND" ] || fail "压缩包里没有找到 whisper.xcframework"
    ditto "$FOUND" "Frameworks/whisper.xcframework"
    rm -rf "$TMP_DIR" "$TMP_ZIP"
    green "  ✓ whisper.xcframework 就绪"
fi

# ── 3. 编译 ────────────────────────────────────────
step "3/6 编译 VoiceFlow（1-3 分钟）"
if swift build -c release 2>&1 | tee build.log; then
    :
fi
BIN=".build/release/VoiceFlow"
[ -f "$BIN" ] || fail "编译失败。请把 VoiceFlow/build.log 的内容发给 Claude，我来修。"
green "  ✓ 编译成功"

# ── 4. 打包 .app ───────────────────────────────────
step "4/6 打包应用"
# 在 /tmp 打包签名：项目目录在 iCloud 同步路径下时，文件会被反复加上
# Finder 扩展属性导致 codesign 报 "detritus not allowed"
rm -rf dist
STAGE=$(mktemp -d)
APP="$STAGE/VoiceFlow.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN" "$APP/Contents/MacOS/VoiceFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"

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

# 嵌入 whisper 动态框架
SLICE=$(find Frameworks/whisper.xcframework -maxdepth 1 -type d -name "macos-*" | head -1)
[ -n "$SLICE" ] || fail "whisper.xcframework 里没有 macOS 架构"
ditto "$SLICE/whisper.framework" "$APP/Contents/Frameworks/whisper.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/VoiceFlow" 2>/dev/null || true

# 彻底清理：AppleDouble 文件、.DS_Store、所有扩展属性
find "$APP" \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
dot_clean -m "$APP" 2>/dev/null || true
xattr -rc "$APP" 2>/dev/null || true

# 签名（本机 ad-hoc，保证权限记忆稳定）
codesign --force -s - "$APP/Contents/Frameworks/whisper.framework" || fail "框架签名失败"
codesign --force -s - "$APP" || fail "签名失败"
codesign --verify --deep "$APP" || fail "签名校验未通过"
green "  ✓ VoiceFlow.app 打包完成"

# ── 5. 下载识别模型 ─────────────────────────────────
step "5/6 下载语音识别模型（本地离线识别用，只需一次）"
MODELS_DIR="$HOME/Library/Application Support/VoiceFlow/models"
mkdir -p "$MODELS_DIR"
if [ "$ARCH" = "arm64" ]; then
    MODEL="ggml-large-v3-turbo-q5_0.bin"   # 约 547MB，Apple Silicon 推荐
else
    MODEL="ggml-small.bin"                  # 约 488MB，Intel 机型均衡之选
fi
if [ -f "$MODELS_DIR/$MODEL" ]; then
    green "  ✓ 模型已存在，跳过下载"
else
    echo "  模型：$MODEL（几百 MB，取决于网速，请耐心等待）"
    download "$MODELS_DIR/$MODEL" \
        "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/$MODEL" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL" \
        || { red "  模型下载失败——不影响安装，稍后可在 App 的 设置 → 识别 里重新下载。"; }
fi

# ── 6. 安装到 /Applications ─────────────────────────
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
touch "$DEST" 2>/dev/null || true   # 刷新访达图标缓存
green "  ✓ 已安装：$DEST"

# 重新编译后签名会变化，旧的「辅助功能」授权会失效（系统界面却仍显示已开启）。
# 这里主动清掉失效授权，让系统重新弹出干净的授权提示。
tccutil reset Accessibility com.ligen.voiceflow >/dev/null 2>&1 || true

open "$DEST"

echo
bold "🎉 安装完成！"
echo
bold "  ⚠️ 重要：每次重新安装后，【辅助功能】都需要重新授权一次："
echo "     系统设置 → 隐私与安全性 → 辅助功能 → 打开 VoiceFlow 开关"
echo "     （如果列表里已有 VoiceFlow 但快捷键没反应：选中它点「−」删除，"
echo "      再点「+」重新添加 $DEST）"
echo
echo "  首次安装还需要：允许【麦克风】权限；在 设置 → AI 润色 里填 OpenAI API Key"
echo
bold "  使用：在任何输入框，轻点【右 Option (⌥)】开始说话，再点一下，文字即输入。"
echo "        录音中按 Esc 取消。快捷键和触发方式可在设置里更改。"
echo
echo "按任意键关闭本窗口…"; read -n 1 -s || true
