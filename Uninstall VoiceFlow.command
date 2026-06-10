#!/bin/bash
# 卸载 VoiceFlow
set -u

echo "正在卸载 VoiceFlow…"
pkill -x VoiceFlow 2>/dev/null || true
sleep 0.5

rm -rf "/Applications/VoiceFlow.app" "$HOME/Applications/VoiceFlow.app" "/Applications/VoiceFlow V3 Lab.app" "$HOME/Applications/VoiceFlow V3 Lab.app"
echo "✓ 已删除应用"

read -p "是否同时删除识别模型和设置？(y/N) " ANSWER
if [ "${ANSWER:-n}" = "y" ] || [ "${ANSWER:-n}" = "Y" ]; then
    rm -rf "$HOME/Library/Application Support/VoiceFlow"
    defaults delete com.ligen.voiceflow 2>/dev/null || true
    defaults delete com.ligen.voiceflow.v3 2>/dev/null || true
    security delete-generic-password -s "com.ligen.voiceflow" -a "openai_api_key" 2>/dev/null || true
    echo "✓ 已删除模型、设置和钥匙串中的 API Key"
fi

echo
echo "卸载完成。按任意键关闭…"
read -n 1 -s || true
