#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "${SCRIPTDIR}/.." && pwd)
REPORT_DIR="${PROJECT_DIR}/reports"
REPORT_FILE="${REPORT_DIR}/system-report-${TIMESTAMP}.txt"

mkdir -p "${REPORT_DIR}"

BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
DOMAIN_NAME=$(grep -E '^DOMAIN_NAME=' "${PROJECT_DIR}/config/settings.env" 2>/dev/null | cut -d= -f2 | tr -d '"')
CONFIG_TOML="${PROJECT_DIR}/config/settings.toml"
API_KEY=""

if [ -f "$CONFIG_TOML" ]; then
  read -r ROUTER_PORT FAST_PORT THINKING_PORT EMBEDDING_PORT OCR_PORT TTS_PORT WHISPER_PORT API_KEY < <(
    python3 - <<'PY'
import tomllib
from pathlib import Path

cfg = tomllib.loads(Path("config/settings.toml").read_text())
services = cfg.get("services", {})
server = cfg.get("server", {})

def port(name, default):
    return services.get(name, {}).get("port", default)

api_keys = server.get("api_keys", [])
api_key = api_keys[0] if api_keys else server.get("api_key", "")

print(
    port("router", 8080),
    port("fast", 8081),
    port("thinking", 8083),
    port("embedding", 8084),
    port("ocr", 8085),
    port("tts", 8086),
    port("whisper", 8087),
    api_key,
)
PY
  )
else
  ROUTER_PORT=8080
  FAST_PORT=8081
  THINKING_PORT=8083
  EMBEDDING_PORT=8084
  OCR_PORT=8085
  TTS_PORT=8086
  WHISPER_PORT=8087
  API_KEY=""
fi

AUTH_HEADER_ARGS=()
if [ -n "${API_KEY}" ]; then
  AUTH_HEADER_ARGS=(-H "Authorization: Bearer ${API_KEY}")
fi

exec >"${REPORT_FILE}" 2>&1

echo "==== mlx-box System Report :: ${TIMESTAMP} ===="
echo
echo "== OS / Kernel =="
sw_vers 2>/dev/null || true
uname -a || true

echo
echo "== Hardware =="
echo -n "RAM (bytes): "; sysctl -n hw.memsize || true
echo -n "CPU: "; sysctl -n machdep.cpu.brand_string 2>/dev/null || true

echo
echo "== Disk Usage =="
df -h / || true
echo "HuggingFace cache size:"
du -sh ~/.cache/huggingface/hub 2>/dev/null || true

echo
echo "== Network (WAN) =="
# Public IP check (optional; remove if concerned about leakage)
echo -n "public_ip: "; curl -s ifconfig.me || true; echo

echo
echo "== Services (launchctl) =="
sudo launchctl list | egrep 'com\.local\.|com\.mlx-box\.|homebrew\.mxcl\.nginx' || true

echo
echo "== Chat / Embed quick checks =="
echo "Router models:"; curl -s "http://127.0.0.1:${ROUTER_PORT}/v1/models" "${AUTH_HEADER_ARGS[@]}" || true; echo
echo "Fast models:"; curl -s "http://127.0.0.1:${FAST_PORT}/v1/models" "${AUTH_HEADER_ARGS[@]}" || true; echo
echo "Thinking models:"; curl -s "http://127.0.0.1:${THINKING_PORT}/v1/models" "${AUTH_HEADER_ARGS[@]}" || true; echo
echo "Embed models:"; curl -s "http://127.0.0.1:${EMBEDDING_PORT}/v1/models" "${AUTH_HEADER_ARGS[@]}" || true; echo
echo "OCR models:"; curl -s "http://127.0.0.1:${OCR_PORT}/v1/models" "${AUTH_HEADER_ARGS[@]}" || true; echo
echo "TTS models:"; curl -s "http://127.0.0.1:${TTS_PORT}/v1/models" "${AUTH_HEADER_ARGS[@]}" || true; echo
echo "Whisper models:"; curl -s "http://127.0.0.1:${WHISPER_PORT}/v1/models" "${AUTH_HEADER_ARGS[@]}" || true; echo

echo
echo "== Nginx =="
echo "Config test:"; sudo nginx -t -c "${BREW_PREFIX}/etc/nginx/nginx.conf" || true
echo "Active 80/443 servers:"; sudo nginx -T -c "${BREW_PREFIX}/etc/nginx/nginx.conf" | egrep -n 'server_name|listen 80|listen 443|allow |deny all' || true

echo
echo "== TLS certs (Let's Encrypt) =="
if [ -n "${DOMAIN_NAME}" ]; then
  sudo ls -l "/etc/letsencrypt/live/${DOMAIN_NAME}" 2>/dev/null || echo "No certs found for ${DOMAIN_NAME}"
fi

echo
echo "== Firewall (pf) =="
sudo pfctl -s info || true
sudo pfctl -sr | head -n 50 || true
echo "States (top 10):"; sudo pfctl -ss | head -n 10 || true

echo
echo "== Logs (tails) =="
echo "Router backend stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.router-backend/stderr.log" 2>/dev/null || true; echo
echo "Fast backend stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.fast-backend/stderr.log" 2>/dev/null || true; echo
echo "Thinking backend stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.thinking-backend/stderr.log" 2>/dev/null || true; echo
echo "Embedding backend stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.embedding-backend/stderr.log" 2>/dev/null || true; echo
echo "OCR backend stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.ocr-backend/stderr.log" 2>/dev/null || true; echo
echo "TTS backend stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.tts-backend/stderr.log" 2>/dev/null || true; echo
echo "Whisper backend stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.whisper-backend/stderr.log" 2>/dev/null || true; echo
echo "Fast stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.fast/stderr.log" 2>/dev/null || true; echo
echo "Thinking stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.thinking/stderr.log" 2>/dev/null || true; echo
echo "Embedding stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.embedding/stderr.log" 2>/dev/null || true; echo
echo "OCR stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.ocr/stderr.log" 2>/dev/null || true; echo
echo "TTS stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.tts/stderr.log" 2>/dev/null || true; echo
echo "Whisper stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.whisper/stderr.log" 2>/dev/null || true; echo
echo "nginx error (last 50):"; tail -n 50 "${BREW_PREFIX}/var/log/nginx/error.log" 2>/dev/null || true; echo

echo "==== End Report (${REPORT_FILE}) ===="

echo "Saved report to: ${REPORT_FILE}" 1>&2
