#!/usr/bin/env bash
# Set up HTTPS for the web frontend using an mkcert CA + Caddy reverse proxy.
# (The browser needs the mkcert root CA installed to trust the mic/HTTPS page.)
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
IP="${GX10_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
[ -n "$IP" ] || { echo "could not detect IP; set GX10_IP=<box-ip>"; exit 1; }

# mkcert auto-download (linux-arm64) if not already present
if ! command -v mkcert >/dev/null 2>&1 && [ ! -x "$GF_BASE/bin/mkcert" ]; then
  echo "[caddy] downloading mkcert (linux-arm64) ..."
  mkdir -p "$GF_BASE/bin"
  curl -L -C - -o "$GF_BASE/bin/mkcert" \
    "https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-linux-arm64" \
    && chmod +x "$GF_BASE/bin/mkcert" || echo "[caddy] mkcert download failed; install it manually into $GF_BASE/bin/"
fi
MKCERT="$GF_BASE/bin/mkcert"
export CAROOT="$GF_BASE/certs"
[ -f "$CAROOT/rootCA.pem" ] || "$MKCERT" -install 2>/dev/null || true
(cd "$GF_BASE" && "$MKCERT" "$IP" || true)   # produces $GF_BASE/<ip>+1.pem and -key.pem

# write Caddyfile
cat > "$GF_BASE/Caddyfile" <<EOF
{
    auto_https off
}
https://${IP}:7861 {
    tls $GF_BASE/${IP}+1.pem $GF_BASE/${IP}+1-key.pem
    handle_path /s2s/* {
        reverse_proxy http://127.0.0.1:8765
    }
    handle_path /lt/* {
        reverse_proxy http://127.0.0.1:8010
    }
    reverse_proxy http://127.0.0.1:7860
}
EOF
echo "Caddyfile written. Root CA at $CAROOT/rootCA.pem — install it on your client browser to use the mic."
echo "Then: ./scripts/start-all.sh"
