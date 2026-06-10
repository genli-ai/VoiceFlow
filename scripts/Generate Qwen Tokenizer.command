#!/bin/bash
# One-time tool: generate tokenizer.json from Qwen's official vocab/merges
# 一次性工具：从 Qwen 官方 vocab/merges 生成 tokenizer.json
set -u

SYS_LANG=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p')
case "$SYS_LANG" in *zh*) ZH=1 ;; *) ZH=0 ;; esac
t() { if [ "$ZH" = "1" ]; then printf "%s" "$1"; else printf "%s" "$2"; fi; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_DIR/VoiceFlow/Resources/QwenTokenizer"
WORK=$(mktemp -d)
cd "$WORK" || exit 1

echo "==> 1/3 $(t "下载 Qwen3-ASR 官方分词器源文件（约 4.5MB）" "Downloading Qwen3-ASR tokenizer sources (~4.5 MB)")"
for F in vocab.json merges.txt tokenizer_config.json; do
    curl -fL --connect-timeout 20 -o "$F" \
        "https://hf-mirror.com/Qwen/Qwen3-ASR-0.6B/resolve/main/$F" \
     || curl -fL --connect-timeout 20 -o "$F" \
        "https://huggingface.co/Qwen/Qwen3-ASR-0.6B/resolve/main/$F" \
     || { echo "✗ $(t "下载失败：" "Download failed: ")$F"; read -n 1 -s; exit 1; }
done

echo "==> 2/3 $(t "转换为 tokenizer.json（首次需安装转换工具，约 1-2 分钟）" "Converting to tokenizer.json (first run installs tools, ~1-2 min)")"
python3 -m venv .venv && source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet "transformers>=4.46" tokenizers || { echo "✗ $(t "安装转换工具失败" "Failed to install conversion tools")"; read -n 1 -s; exit 1; }

python3 - <<'EOF' || { echo "✗ $(t "转换失败" "Conversion failed")"; read -n 1 -s; exit 1; }
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained(".", use_fast=True)
tok.save_pretrained("out", legacy_format=False)
# 验证音频特殊 token 是不可拆分的整体（否则模型提示词会坏）
ids = tok("<|audio_start|><|audio_pad|><|audio_end|>")["input_ids"]
print("audio special token ids:", ids)
assert len(ids) == 3, f"音频特殊 token 没有被原子化编码：{ids}"
print("OK")
EOF

[ -f "out/tokenizer.json" ] || { echo "✗ $(t "没有生成 tokenizer.json" "tokenizer.json was not generated")"; read -n 1 -s; exit 1; }

echo "==> 3/3 $(t "存入仓库资源" "Saving into repo resources")"
mkdir -p "$OUT_DIR"
cp out/tokenizer.json "$OUT_DIR/tokenizer.json"
ls -lh "$OUT_DIR/tokenizer.json"

echo
echo "✅ $(t "完成！现在重新运行安装脚本，App 会自动把它补进模型目录。" "Done! Re-run the installer — the app will copy it into the model directory automatically.")"
echo "$(t "按任意键关闭…" "Press any key to close…")"; read -n 1 -s || true
