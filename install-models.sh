#!/usr/bin/env bash
# Download all models needed for the AI girlfriend onto the GX10.
# Run as normal user (no sudo). Tolerant of slow networks: resumable, with mirror.
# Usage: ./install-models.sh   (or ./setup.sh --only-models)
set -euo pipefail

GF_BASE="${GF_BASE:-$HOME/ai-gf}"
MODELS="$GF_BASE/models"
export HF_HOME="${HF_HOME:-$GF_BASE/hf_home}"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
PY="$GF_BASE/speech-venv/bin/python"
log(){ printf '\033[1;32m[models]\033[0m %s\n' "$*"; }

mkdir -p "$MODELS"

HF() { # HF <model_repo> <local_dir>
  log "downloading $1 -> $2"
  "$PY" - "$1" "$2" <<'PYEOF'
import sys, os
from huggingface_hub import snapshot_download
repo, dest = sys.argv[1], sys.argv[2]
os.makedirs(dest, exist_ok=True)
snapshot_download(repo_id=repo, local_dir=dest, resume_download=True)
print("done:", repo)
PYEOF
}

# 1) 大腦 LLM (Qwen3.6-35B-A3B uncensored, Q4_K_M) — big (~21GB)
log "==> LLM (21GB, may take hours on slow network)"
LLM_FILE="Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
if [ ! -f "$MODELS/$LLM_FILE" ]; then
  url="https://huggingface.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/resolve/main/${LLM_FILE}"
  curl -L -C - -o "$MODELS/${LLM_FILE}.part" "$url" && mv "$MODELS/${LLM_FILE}.part" "$MODELS/${LLM_FILE}" \
    || log "warn: LLM download via direct URL failed; run again (resumes)"
else
  log "LLM already present, skipping"
fi

# 2) Qwen3-TTS (voice clone)
HF "Qwen/Qwen3-TTS-12Hz-1.7B-Base" "$MODELS/qwen-tts/Qwen3-TTS-12Hz-1.7B-Base"

# 3) Paraformer ASR (zh)
HF "modelscope/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch" \
   "$MODELS/funasr/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch"

# 4) wav2lip avatar weights (bundled in assets too) — if not present, fetch
if [ ! -f "$MODELS/wav2lip256.pth" ]; then
  log "download wav2lip256.pth (see docs for URL / or copy from assets)"
fi

log "All model downloads done."
