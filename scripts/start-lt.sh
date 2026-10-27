#!/usr/bin/env bash
# Start LiveTalking (小雅 avatar) on port 8010 via WebRTC.
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
cd "$GF_BASE/livetalking/LiveTalking"
export PYTHONPATH="$GF_BASE/livetalking/LiveTalking"
export PATH="$GF_BASE/bin:$PATH"
AVATAR_ID="${AVATAR_ID:-wav2lip256_xiaoya}"
exec "$GF_BASE/musetalk-venv/bin/python" app.py \
  --transport webrtc --model wav2lip --avatar_id "$AVATAR_ID" \
  --stun "stun:stun.l.google.com:19302"
