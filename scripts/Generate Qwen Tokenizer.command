#!/bin/bash
# 一次性工具：从 Qwen 官方 vocab/merges 生成 tokenizer.json（swift-transformers 需要，
# 但 HF 上所有 Qwen3-ASR 仓库都不带）。生成结果存入仓库资源，之后 App 自动使用。
set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_DIR/VoiceFlow/Resources/QwenTokenizer"
WORK=$(mktemp -d)
cd "$WORK" || exit 1

echo "==> 1/3 下载 Qwen3-ASR 官方分词器源文件（约 4.5MB）"
for F in vocab.json merges.txt tokenizer_config.json; do
    curl -fL --connect-timeout 20 -o "$F" \
        "https://hf-mirror.com/Qwen/Qwen3-ASR-0.6B/resolve/main/$F" \
     || curl -fL --connect-timeout 20 -o "$F" \
        "https://huggingface.co/Qwen/Qwen3-ASR-0.6B/resolve/main/$F" \
     || { echo "✗ 下载 $F 失败"; read -n 1 -s; exit 1; }
done

echo "==> 2/3 转换为 tokenizer.json（首次需安装转换工具，约 1-2 分钟）"
python3 -m venv .venv && source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet "transformers>=4.46" tokenizers || { echo "✗ 安装转换工具失败"; read -n 1 -s; exit 1; }

python3 - <<'EOF' || { echo "✗ 转换失败"; read -n 1 -s; exit 1; }
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained(".", use_fast=True)
tok.save_pretrained("out", legacy_format=False)
# 验证音频特殊 token 是不可拆分的整体（否则模型提示词会坏）
ids = tok("<|audio_start|><|audio_pad|><|audio_end|>")["input_ids"]
print("audio special token ids:", ids)
assert len(ids) == 3, f"音频特殊 token 没有被原子化编码：{ids}"
print("OK")
EOF

[ -f "out/tokenizer.json" ] || { echo "✗ 没有生成 tokenizer.json"; read -n 1 -s; exit 1; }

echo "==> 3/3 存入仓库资源"
mkdir -p "$OUT_DIR"
cp out/tokenizer.json "$OUT_DIR/tokenizer.json"
ls -lh "$OUT_DIR/tokenizer.json"

echo
echo "✅ 完成！现在重新运行「Install VoiceFlow V2.command」，App 会自动把它补进模型目录。"
echo "按任意键关闭…"; read -n 1 -s || true
