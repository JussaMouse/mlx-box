#!/bin/bash
#
# A simple, robust script to update the chat model.
#

set -e

# --- Configuration ---
readonly CONFIG_FILE="config/settings.toml"
readonly SERVICE_NAME="com.local.mlx-chat-server"

# --- Helper Functions ---

log() {
    echo "🔵 [MODEL-UPDATER] $1"
}

success() {
    echo "✅ [MODEL-UPDATER] $1"
}

# --- Argument Check ---

if [ -z "$1" ]; then
  echo "Usage: $0 <huggingface-model-id>"
  echo "Example: $0 mlx-community/Llama-3-8B-Instruct-4bit"
  exit 1
fi
readonly MODEL_ID="$1"

# --- Main Script ---

log "Starting model update process for: ${MODEL_ID}"

# 1. Update the configuration file using a simple sed command.
log "Updating configuration file at '${CONFIG_FILE}'..."
# Escape slashes in the model ID so they don't break the sed command
ESCAPED_MODEL_ID=$(echo "$MODEL_ID" | sed 's/[/]/\\&/g')
# Use sed to find the [services.chat] section and replace the model line.
# This works on macOS's version of sed.
sed -i '' "/\\[services\\.chat\\]/,/\\[/s/^\\( *model *= *\\).*/\\1\"${ESCAPED_MODEL_ID}\"/" "$CONFIG_FILE"
success "Configuration updated."

# 2. Restart the chat service to apply the changes.
log "Restarting chat service ('${SERVICE_NAME}')..."
# Use stop/start for a more reliable restart that preserves the working directory.
sudo launchctl stop "${SERVICE_NAME}" 2>/dev/null || true
sleep 2 # Give the service a moment to fully stop.
sudo launchctl start "${SERVICE_NAME}"
success "Service restarted. Download should begin shortly."

# 3. Monitor the log file for download progress.
REAL_USER=${SUDO_USER:-$(whoami)}
LOG_FILE="/Users/${REAL_USER}/Library/Logs/${SERVICE_NAME}/stderr.log"
LOG_DIR=$(dirname "${LOG_FILE}")

log "Monitoring download progress. Press Ctrl+C after you see the 'Model loaded' message."

# Ensure the log directory exists and clear the old log file.
mkdir -p "${LOG_DIR}"
sleep 2 # Give the service a moment to start up.
> "$LOG_FILE"

# Display the raw log file. This is simpler and more reliable than a progress bar.
tail -f "$LOG_FILE"
