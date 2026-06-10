#!/bin/bash
# 重装 Xcode 命令行工具（修复 PackageDescription 库损坏问题）
set -u

echo "╔══════════════════════════════════════════╗"
echo "║   重装 Xcode 命令行工具（约 5 分钟）       ║"
echo "╚══════════════════════════════════════════╝"
echo
echo "检测到命令行工具安装损坏（接口与库版本不匹配），需要删除后重装。"
echo
echo "下面需要输入你的 Mac 开机密码（输入时屏幕上不会显示，输完按回车）："
echo

if ! sudo rm -rf /Library/Developer/CommandLineTools; then
    echo "✗ 删除失败（密码错误或没有管理员权限）"
    echo "按任意键退出…"; read -n 1 -s || true
    exit 1
fi
echo "✓ 已删除旧版命令行工具"
echo

xcode-select --install 2>/dev/null || true
echo "已请求安装。请在弹出的窗口中点「安装」并等待完成。"
echo
echo "★ 安装完成后，重新双击「Install VoiceFlow.command」即可。"
echo
echo "按任意键关闭本窗口…"; read -n 1 -s || true
