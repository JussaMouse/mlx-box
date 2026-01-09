#!/bin/bash
#
# A robust script to update specific model tiers.
#

set -e

# --- Configuration ---
readonly CONFIG_FILE="config/settings.toml"

# --- Helper Functions ---

log() {
    echo "🔵 [MODEL-UPDATER] $1"
}

success() {
    echo "✅ [MODEL-UPDATER] $1"
}

error() {
    echo "❌ [MODEL-UPDATER] $1"
    exit 1
}

# --- Argument Check ---

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <service-tier> <huggingface-model-id>"
  echo "Tiers: router, fast, thinking"
  echo "Example: $0 fast mlx-community/Qwen3-30B-A3B-4bit"
  exit 1
fi

readonly TIER="$1"
readonly MODEL_ID="$2"
readonly SERVICE_NAME="com.local.mlx-${TIER}"

if [[ ! "$TIER" =~ ^(router|fast|thinking)$ ]]; then
    error "Invalid tier: $TIER. Must be 'router', 'fast', or 'thinking'."
fi

# --- Main Script ---

log "Starting update for TIER: ${TIER}"
log "New Model ID: ${MODEL_ID}"

# 1. Update the configuration file using sed.
log "Updating configuration file at '${CONFIG_FILE}'..."

# Escape slashes in the model ID
ESCAPED_MODEL_ID=$(echo "$MODEL_ID" | sed 's/[/]/\\&/g')

# Use sed to find the specific [services.TIER] section and replace the model line within it.
# This requires a slightly more complex sed command to ensure we are editing the right section.
# We match from [services.tier] to the next [section] or end of file.
# Note: macOS sed -i '' requires the empty string arg.

sed -i '' "/\\[services\\.${TIER}\\]/,/\\[/s/^\\( *model *= *\\).*/\\1\"${ESCAPED_MODEL_ID}\"/" "$CONFIG_FILE"

success "Configuration updated."

# 2. Restart the specific service.
log "Restarting service ('${SERVICE_NAME}')..."

sudo launchctl stop "${SERVICE_NAME}" 2>/dev/null || true
sleep 2
sudo launchctl start "${SERVICE_NAME}"

success "Service restarted. Download should begin shortly."

# 3. Monitor log
REAL_USER=${SUDO_USER:-$(whoami)}
LOG_FILE="/Users/${REAL_USER}/Library/Logs/${SERVICE_NAME}/stderr.log"

log "Monitoring log: ${LOG_FILE}"
log "Press Ctrl+C once you see the model load."

mkdir -p "$(dirname "$LOG_FILE")"
sleep 2
tail -f "$LOG_FILE"
