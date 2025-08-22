#!/bin/bash
set -euo pipefail

# Collect basic system information and write to config/system-info.env
# Usage: run from anywhere; will write to the project's config/ directory

SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "${SCRIPTDIR}/.." && pwd)
OUT_FILE="${PROJECT_DIR}/config/system-info.env"

mkdir -p "$(dirname "${OUT_FILE}")"

OS_NAME="$(sw_vers -productName 2>/dev/null || uname -s)"
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || uname -r)"
KERNEL="$(uname -sr)"
CPU="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -p)"
MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
DISK_AVAIL="$(df -h / | awk 'NR==2{print $4}')"
PRIMARY_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")"
HUGGINGFACE_CACHE="${HOME}/.cache/huggingface/hub"

cat > "${OUT_FILE}" << EOF
# Auto-generated system info
OS_NAME="${OS_NAME}"
OS_VERSION="${OS_VERSION}"
KERNEL="${KERNEL}"
CPU="${CPU}"
MEM_BYTES="${MEM_BYTES}"
DISK_AVAIL="${DISK_AVAIL}"
PRIMARY_IP="${PRIMARY_IP}"
HUGGINGFACE_CACHE="${HUGGINGFACE_CACHE}"
PROJECT_DIR="${PROJECT_DIR}"
EOF

# Ensure file is owned by the current user
chown "$(whoami)" "${OUT_FILE}" 2>/dev/null || true

echo "Saved system information to ${OUT_FILE}"


