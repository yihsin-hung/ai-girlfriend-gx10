#!/usr/bin/env bash
# Start Caddy reverse proxy (HTTPS :7861) -> s2s / livetalking / frontend.
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
exec "$GF_BASE/bin/caddy" run --config "$GF_BASE/Caddyfile" --adapter caddyfile
