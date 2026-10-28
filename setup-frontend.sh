#!/usr/bin/env bash
# Deploy the web frontend (hf-realtime-voice) and apply the two critical fixes:
#   1) AUDIO_SAMPLE_RATE -> 16000 (the s2s pipeline delivers 16kHz; playing at 24kHz
#      makes the voice sound like a *different person*).
#   2) DEFAULT_INSTRUCTIONS -> Chinese 小雅 persona (so replies are Traditional Chinese).
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
FRONTEND="$GF_BASE/hf-realtime-voice"
FRONTEND_REPO="${FRONTEND_REPO:-https://huggingface.co/spaces/smolagents/hf-realtime-voice}"
VENVPY="$GF_BASE/speech-venv/bin/python"

if [ ! -d "$FRONTEND" ]; then
  echo "cloning frontend from $FRONTEND_REPO"
  git clone --depth 1 "$FRONTEND_REPO" "$FRONTEND"
fi
cd "$FRONTEND"

echo "[frontend] installing requirements"
[ -f requirements.txt ] && "$GF_BASE/speech-venv/bin/pip" install -r requirements.txt || true

# avatar-sync.js (digital human relay layer) from this repo's assets
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$REPO/assets/avatar-sync.js" ]; then
  cp "$REPO/assets/avatar-sync.js" "$FRONTEND/avatar-sync.js"
  echo "[frontend] copied avatar-sync.js"
fi

# patch server.py to serve avatar-sync.js and index.html to include it (idempotent)
"$VENVPY" - "$FRONTEND" <<'PYEOF'
import sys, os, shutil, re
root = sys.argv[1]
MARK = "# --- avatar-sync patch ---"
srv = next((os.path.join(root, n) for n in ("server.py","app.py","main.py") if os.path.exists(os.path.join(root,n))), None)
if srv:
    src = open(srv, encoding="utf-8").read()
    if MARK not in src:
        shutil.copy(srv, srv+".bak")
        src += f'''
{MARK}
import os as _av_os
from fastapi.responses import FileResponse as _AvFile
@app.get("/avatar-sync.js", include_in_schema=False)
async def _avatar_sync_js():
    return _AvFile(_av_os.path.join(_av_os.path.dirname(_av_os.path.abspath(__file__)), "avatar-sync.js"), media_type="application/javascript")
'''
        open(srv,"w",encoding="utf-8").write(src)
        print("[frontend] patched server.py to serve avatar-sync.js")
idx = next((os.path.join(root,c) for c in ("index.html","static/index.html","templates/index.html") if os.path.exists(os.path.join(root,c))), None)
TAG = '<script src="/avatar-sync.js"></script>'
if idx:
    html = open(idx, encoding="utf-8").read()
    if "avatar-sync.js" not in html:
        shutil.copy(idx, idx+".bak")
        m = re.search(r'<script[^>]*src=["\'][^"\']*(main|index|app)[^"\']*\.js["\'][^>]*>', html)
        if m: html = html[:m.start()] + TAG + "\n    " + html[m.start():]
        elif "</body>" in html: html = html.replace("</body>", f"  {TAG}\n</body>", 1)
        else: html = TAG + "\n" + html
        open(idx,"w",encoding="utf-8").write(html)
        print("[frontend] patched index.html to include avatar-sync.js")
PYEOF

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
