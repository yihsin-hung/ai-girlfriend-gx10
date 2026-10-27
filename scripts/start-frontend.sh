#!/usr/bin/env bash
# Start the web frontend (hf-realtime-voice) on port 7860.
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
cd "$GF_BASE/hf-realtime-voice"
export SPEECH_TO_SPEECH_URL="${SPEECH_TO_SPEECH_URL:-ws://localhost:8765/v1/realtime}"
exec "$GF_BASE/speech-venv/bin/uvicorn" server:app --host 0.0.0.0 --port 7860
