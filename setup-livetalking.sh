#!/usr/bin/env bash
# Deploy LiveTalking (小雅 digital-human avatar) + musetalk venv.
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
VENV_LT="$GF_BASE/musetalk-venv"
LT_DIR="$GF_BASE/livetalking"
LT_REPO="${LT_REPO:-https://github.com/lipku/LiveTalking.git}"
AVATAR_ID="${AVATAR_ID:-wav2lip256_xiaoya}"

# clone LiveTalking if not present
if [ ! -d "$LT_DIR/LiveTalking" ]; then
  echo "cloning LiveTalking"
  git clone --depth 1 "$LT_REPO" "$LT_DIR/LiveTalking"
fi

# install deps into the LT venv (torch/cv2/librosa; reuse from speech-venv if present to save download)
"$VENV_LT/bin/pip" install -U pip wheel || true
"$VENV_LT/bin/pip" install \
  /home/asus/ai-gf/speech-venv/lib/python3.12/site-packages/*.whl 2>/dev/null \
  torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu128 || \
  "$VENV_LT/bin/pip" install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu128 || true

# wav2lip weights -> models/wav2lip.pth (LiveTalking expects this exact filename)
if [ ! -f "$GF_BASE/models/wav2lip.pth" ]; then
  echo "[lt] find wav2lip256.pth ..."
  for src in "$HOME/AI/wav2lip256.pth" "$HOME/一键部署包/AI/wav2lip256.pth" "$REPO_ASSETS/wav2lip256.pth"; do
    [ -f "$src" ] && cp "$src" "$GF_BASE/models/wav2lip.pth" && break
  done
fi
# if we still don't have it, try the HF mirror
if [ ! -f "$GF_BASE/models/wav2lip.pth" ]; then
  echo "[lt] downloading wav2lip.pth from HF mirror ..."
  curl -L -C - -o "$GF_BASE/models/wav2lip.pth.part" \
    "https://huggingface.co/shibing624/ai-avatar-wav2lip/resolve/main/wav2lip.pth" \
    && mv "$GF_BASE/models/wav2lip.pth.part" "$GF_BASE/models/wav2lip.pth" || true
fi

echo "LiveTalking deps ready. Generating the 小雅 avatar (img_size=256) via the LiveTalking API..."
# Start LiveTalking briefly, then call its avatar API exactly as the working
# 小雅 avatar was produced (img_size=256 avoids the 2x2-conv crash seen with 96px).
AVATAR_ID="${AVATAR_ID:-wav2lip256_xiaoya}"
if command -v tmux >/dev/null 2>&1; then
  tmux kill-session -t lt 2>/dev/null || true
  REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  tmux new-session -d -s lt "bash $REPO/scripts/start-lt.sh"
  echo "waiting for LiveTalking to come up on :8010 ..."
  for i in $(seq 1 60); do
    if curl -s "http://127.0.0.1:8010/api/avatar/status" >/dev/null 2>&1; then break; fi
    sleep 2
  done
  echo "generate avatar $AVATAR_ID ..."
  curl -s -X POST "http://127.0.0.1:8010/api/avatar/task" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"wav2lip\",\"avatar_id\":\"$AVATAR_ID\",\"video_path\":\"$GF_BASE/setup/idle.mp4\",\"img_size\":256}" \
    | head -c 300 || true
  echo ""
  echo "Note: verify the avatar was generated (face_imgs should be 256x256). If not, use Lifetalking /avatar.html."
else
  echo "tmux not found — start LiveTalking then generate the avatar via /avatar.html (img_size=256)."
fi
echo "LiveTalking ready."
