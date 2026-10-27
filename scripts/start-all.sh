#!/usr/bin/env bash
# One-command startup of all AI-girlfriend services on the GX10 (via tmux).
# Usage: ./scripts/start-all.sh
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmx(){ # tmx <name> <cmd> — start a detached tmux session if not already up
  if tmux has-session -t "$1" 2>/dev/null; then echo "[$1] already running"; return; fi
  tmux new-session -d -s "$1" "$2"
  echo "[$1] started"
}

# kill any stale instances first so ports are free
for pat in "speech-to-speech --mode" "uvicorn server:app" "app.py --transport webrtc" "caddy run"; do
  pkill -f "$pat" 2>/dev/null || true
done
sleep 3

# order matters: LLM first (the s2s needs it up); start it once, in tmux
tmx llm   "bash $SCRIPT_DIR/start-llama-server.sh"
tmx s2s   "bash $SCRIPT_DIR/start-s2s.sh"
tmx front "$SCRIPT_DIR/start-frontend.sh"
tmx lt    "bash $SCRIPT_DIR/start-lt.sh"
tmx caddy "bash $SCRIPT_DIR/start-caddy.sh"

echo ""
echo "All services launched. Wait ~2 min for model load, then open:"
echo "   https://<GX10-IP>:7861   (HTTPS; install the CA cert first — see README)"
echo "   Firefox on the box: http://localhost:7860"
echo "Check status:  tmux ls    |   logs: tmux attach -t s2s"
