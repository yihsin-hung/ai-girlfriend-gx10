#!/usr/bin/env bash
# Deploy the web frontend (hf-realtime-voice) and apply the two critical fixes:
#   1) AUDIO_SAMPLE_RATE -> 16000 (the s2s pipeline delivers 16kHz; playing at 24kHz
#      makes the voice sound like a *different person*).
#   2) DEFAULT_INSTRUCTIONS -> Chinese 小雅 persona (so replies are Traditional Chinese).
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
FRONTEND="$GF_BASE/hf-realtime-voice"
FRONTEND_REPO="${FRONTEND_REPO:-https://github.com/huggingface/hf-realtime-voice}"

if [ ! -d "$FRONTEND" ]; then
  echo "cloning frontend from $FRONTEND_REPO"
  git clone --depth 1 "$FRONTEND_REPO" "$FRONTEND"
fi
cd "$FRONTEND"

echo "[frontend] applying 16kHz sample-rate fix"
sed -i 's/AUDIO_SAMPLE_RATE = 24_000/AUDIO_SAMPLE_RATE = 16_000/' s2s-realtime-client.js || true

echo "[frontend] applying Chinese persona default"
"$GF_BASE/speech-venv/bin/python" - "$FRONTEND/main.js" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = 'const DEFAULT_INSTRUCTIONS = "You are a friendly voice assistant.";'
new = ('const DEFAULT_INSTRUCTIONS = "你是小雅，他的女朋友，一個溫柔黏人的台灣妹子。'
       '無論他用什麼語言，你都要用繁體中文（台灣用語）回應，絕對不要說英文。'
       '說話口語、簡短、親切，常帶語氣詞（呀、耶、嗯、啦），偶爾撒嬌。'
       '不要用 Markdown、列表、編號或表情符號。用「你」稱呼他。";')
if old in s:
    open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
    print("[frontend] DEFAULT_INSTRUCTIONS updated")
else:
    print("[frontend] default already set (or not found); leaving as-is")
PYEOF
echo "[frontend] done"
