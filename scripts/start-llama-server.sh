#!/usr/bin/env bash
# Start the local llama.cpp OpenAI-compatible server (the LLM "brain") on port 8090.
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
MODELS="$GF_BASE/models"
LLM_FILE="Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
LLM_FULL="$MODELS/$LLM_FILE"
PORT="${LLM_PORT:-8090}"
CTX="${LLM_CTX:-16384}"

[ -f "$LLM_FULL" ] || { echo "model missing: $LLM_FULL (run install-models.sh)"; exit 1; }

docker rm -f llama-server 2>/dev/null || true
docker run -d --name llama-server --gpus all --restart unless-stopped \
  -p "${PORT}:${PORT}" \
  -v "$MODELS:/models" \
  ghcr.io/ggml-org/llama.cpp:server-cuda \
  -m "/models/$LLM_FILE" --alias Qwen3-14B \
  -ngl 99 --host 0.0.0.0 --port "${PORT}" --ctx-size "${CTX}" --parallel 1

echo "llama-server starting on port ${PORT}; waiting for model load..."
for i in $(seq 1 60); do
  if curl -s "http://localhost:${PORT}/v1/models" >/dev/null 2>&1; then echo "up."; break; fi
  sleep 2
done
