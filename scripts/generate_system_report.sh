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
echo "Chat models:"; curl -s http://127.0.0.1:8080/v1/models || true; echo
echo "Embed models:"; curl -s http://127.0.0.1:8081/v1/models || true; echo

echo
echo "== Frontend =="
curl -s -I http://127.0.0.1:8000 || true

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
echo "Chat stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.local.mlx-chat-server/stderr.log" 2>/dev/null || true; echo
echo "Embed stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.local.embed-server/stderr.log" 2>/dev/null || true; echo
echo "Frontend stderr (last 50):"; tail -n 50 "${HOME}/Library/Logs/com.mlx-box.frontend-server/stderr.log" 2>/dev/null || true; echo
echo "nginx error (last 50):"; tail -n 50 "${BREW_PREFIX}/var/log/nginx/error.log" 2>/dev/null || true; echo

echo "==== End Report (${REPORT_FILE}) ===="

echo "Saved report to: ${REPORT_FILE}" 1>&2

