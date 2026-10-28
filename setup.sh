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

# ---- model identifiers (download handled by install-models.sh) ----------
LLM_MODEL_REPO="HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive"
LLM_MODEL_FILE="Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
TTS_MODEL="Qwen/Qwen3-TTS-12Hz-1.7B-Base"
STT_ASR="modelscope/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch"

log(){ printf '\n\033[1;32m[setup]\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31m[error]\033[0m %s\n' "$*"; exit 1; }

# ---------------------------------------------------------------- helpers
ensure_cmds(){ for c in git python3 curl wget; do command -v $c >/dev/null || err "missing: $c (install it first)"; done; }

mkv(){ cd "$GF_BASE" && python3 -m venv "$1" && echo "$1 venv ready"; }

# ---------------------------------------------------------------- main
main(){
  # handle --only-models (just (re)download the model files and exit)
  if [ "$1" = "--only-models" ]; then
    ensure_cmds
    mkdir -p "$GF_BASE" "$MODELS"
    [ -x "$VENV_SPEECH/bin/python" ] || mkv "$VENV_SPEECH"
    "$VENV_SPEECH/bin/pip" install -U pip wheel huggingface_hub -q || true
    log "==> Downloading models only"
    "$GF_REPO/install-models.sh"
    exit 0
  fi

  ensure_cmds
  mkdir -p "$GF_BASE" "$MODELS" "$SETUP"

  log "==> Installing / verifying Python venvs"
  [ -x "$VENV_SPEECH/bin/python" ] || mkv "$VENV_SPEECH"
  [ -x "$VENV_LT/bin/python" ]     || mkv "$VENV_LT"

  log "==> Installing speech-to-speech deps + STT/TTS libs"
  export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.org/simple}"
  "$VENV_SPEECH/bin/pip" install -U pip wheel || true
  "$VENV_SPEECH/bin/pip" install speech-to-speech==0.2.10 faster-whisper faster-qwen3-tts funasr || \
    log "warn: core speech-to-speech install failed, see docs"
  # torch + CUDA wheels. On aarch64 (GX10/GB10) use the NVIDIA-built index; fall back to PyPI.
  if ! "$VENV_SPEECH/bin/pip" install torch --index-url https://download.pytorch.org/whl/cu128 2>/dev/null; then
    log "warn: cu128 index failed on this arch, trying PyPI torch..."
    "$VENV_SPEECH/bin/pip" install torch || true
  fi

  log "==> Downloading models"
  "$GF_REPO/install-models.sh"

  log "==> Preparing llama-server script (started later via start-all.sh)"
  chmod +x "$GF_REPO/scripts/start-llama-server.sh" 2>/dev/null || true
  # NOTE: services are started by ./scripts/start-all.sh AFTER setup, so a
  # partially-downloaded model (big LLM) won't abort this install.

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
