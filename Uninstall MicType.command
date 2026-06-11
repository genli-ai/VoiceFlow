#!/bin/bash
# Uninstall MicType (also cleans up the old "VoiceFlow" install, if present)
# 卸载 MicType（如有旧版 VoiceFlow 安装，一并清理）
set -u

SYS_LANG=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p')
case "$SYS_LANG" in *zh*) ZH=1 ;; *) ZH=0 ;; esac
t() { if [ "$ZH" = "1" ]; then printf "%s" "$1"; else printf "%s" "$2"; fi; }

echo "$(t "正在卸载 MicType…" "Uninstalling MicType…")"
pkill -x MicType 2>/dev/null || true
pkill -x VoiceFlow 2>/dev/null || true
sleep 0.5

rm -rf "/Applications/MicType.app" "$HOME/Applications/MicType.app" \
       "/Applications/VoiceFlow.app" "$HOME/Applications/VoiceFlow.app" \
       "/Applications/VoiceFlow V3 Lab.app" "$HOME/Applications/VoiceFlow V3 Lab.app"
echo "✓ $(t "已删除应用（含旧版 VoiceFlow，如有）" "App removed (including legacy VoiceFlow, if any)")"

read -p "$(t "是否同时删除识别模型和设置？(y/N) " "Also delete the speech model and settings? (y/N) ")" ANSWER
if [ "${ANSWER:-n}" = "y" ] || [ "${ANSWER:-n}" = "Y" ]; then
    rm -rf "$HOME/Library/Application Support/MicType" \
           "$HOME/Library/Application Support/VoiceFlow"
    defaults delete com.ligen.mictype 2>/dev/null || true
    defaults delete com.ligen.voiceflow 2>/dev/null || true
    defaults delete com.ligen.voiceflow.v3 2>/dev/null || true
    for SVC in com.ligen.mictype com.ligen.voiceflow; do
        for ACCT in openai_api_key deepseek_api_key api_key; do
            security delete-generic-password -s "$SVC" -a "$ACCT" 2>/dev/null || true
        done
    done
    echo "✓ $(t "已删除模型、设置和钥匙串中的 API Key" "Model, settings, and Keychain API keys removed")"
fi

echo
echo "$(t "卸载完成。按任意键关闭…" "Done. Press any key to close…")"
read -n 1 -s || true
