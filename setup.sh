#!/usr/bin/env bash
#
# AI Girlfriend (小雅) — one-click setup script for ASUS GX10 (GB10, aarch64, no sudo)
#
# Usage:  ./setup.sh            # fresh install
#         ./setup.sh --only-models   # only (re)download models
#
# This sets up under $GF_BASE (default ~/ai-gf). Run as the normal user (no sudo).
set -euo pipefail

# ---------------------------------------------------------------- config
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
GF_REPO="${GF_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"   # this repo's checkout
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"                    # model mirror (use hf-mirror for CN)
PYVER="3.12"
VENV_SPEECH="$GF_BASE/speech-venv"
VENV_LT="$GF_BASE/musetalk-venv"
MODELS="$GF_BASE/models"
SETUP="$GF_BASE/setup"
FRONTEND="$GF_BASE/hf-realtime-voice"
LIVETALK="$GF_BASE/livetalking/LiveTalking"

# ---- model identifiers / URLs -------------------------------------
LLAMA_REPO="ggml-org/llama.cpp"
LLAMA_DOCKER="ghcr.io/ggml-org/llama.cpp:server-cuda"
LLM_MODEL_REPO="HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive"
LLM_MODEL_FILE="Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
LLM_MODEL_URL="https://huggingface.co/${LLM_MODEL_REPO}/resolve/main/${LLM_MODEL_FILE}"
TTS_MODEL="Qwen/Qwen3-TTS-12Hz-1.7B-Base"
STT_ASR="modelscope/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch"
WAV2LIP_PTH="https://huggingface.co/.../wav2lip256.pth"   # see docs; the bundled one lives in assets/ too

log(){ printf '\n\033[1;32m[setup]\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

# ---------------------------------------------------------------- helpers
ensure_cmds(){ for c in git python3 curl wget; do command -v $c >/dev/null || err "missing: $c (install it first)"; done; }

mkv(){ cd "$GF_BASE" && python3 -m venv "$1" && echo "$1 venv ready"; }

# --------- download with resume + mirror fallback ------------------
fetch(){ # fetch <url> <dest>  — resumable
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ]; then
    # allow re-download only when bigger expected (loose check); keep existing if present & nonzero
    local sz; sz=$(stat -c%s "$dest" 2>/dev/null || echo 0)
    if [ "$sz" -gt 0 ]; then log "already have $(basename "$dest") (${sz} bytes)"; return 0; fi
  fi
  log "downloading $(basename "$dest") ..."
  ( cd "$(dirname "$dest")" && curl -L -C - -o "$dest.part" "$url" && mv "$dest.part" "$dest" ) \
    || { err "download failed: $url  (retry with HF_ENDPOINT set to your mirror)"; }
}

# ---------------------------------------------------------------- main
main(){
  ensure_cmds
  mkdir -p "$GF_BASE" "$MODELS" "$SETUP"

  log "==> Installing / verifying Python venvs"
  [ -x "$VENV_SPEECH/bin/python" ] || mkv "$VENV_SPEECH"
  [ -x "$VENV_LT/bin/python" ]     || mkv "$VENV_LT"

  log "==> Installing speech-to-speech deps + STT/TTS libs"
  export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.org/simple}"
  "$VENV_SPEECH/bin/pip" install -U pip wheel || true
  "$VENV_SPEECH/bin/pip" install speech-to-speech faster-whisper faster-qwen3-tts funasr torch --extra-index-url https://download.pytorch.org/whl/cu128 || \
    log "warn: torch/cu128 extra index may need aarch64 wheel; see docs"

  log "==> Downloading models"
  "$GF_REPO/install-models.sh"

  log "==> Setting up llama-server (docker)"
  "$GF_REPO/scripts/start-llama-server.sh"

  log "==> Setting up the web frontend (hf-realtime-voice) with voice+language fixes"
  "$GF_REPO/setup-frontend.sh"

  log "==> Setting up LiveTalking avatar (小雅)"
  "$GF_REPO/setup-livetalking.sh"

  log "==> Generating HTTPS cert + Caddy config"
  "$GF_REPO/setup-caddy.sh"

  log "==> Copying assets (ref.wav, idle.mp4) into place"
  cp -n "$GF_REPO/assets/ref.wav"  "$SETUP/ref.wav"  || true
  cp -n "$GF_REPO/assets/idle.mp4" "$SETUP/idle.mp4" || true
  # convert ref to 16k mono (required for voice cloning)
  if command -v ffmpeg >/dev/null; then
    cp -n "$SETUP/ref.wav" "$SETUP/ref_orig.wav" || true
    ffmpeg -y -i "$SETUP/ref_orig.wav" -ac 1 -ar 16000 -c:a pcm_s16le "$SETUP/ref.wav" || true
  fi

  log "==> Applying voice-clone + language patches to speech_to_speech"
  "$VENV_SPEECH/bin/python" "$GF_REPO/patches/apply-patches.py"

  log ""
  log "==============================================================="
  log "  Done! On your browser open:  https://<GX10-IP>:7861"
  log "  Start services:  ./scripts/start-all.sh"
  log "==============================================================="
}

main "$@"
