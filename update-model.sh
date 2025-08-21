#!/bin/bash
#
# A script to update the chat model and monitor the download progress.
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
  echo "Example: $0 mlx-community/Llama3-8B-Medicine-4bit"
  exit 1
fi
readonly MODEL_ID="$1"

# --- Main Script ---

log "Starting model update process for: ${MODEL_ID}"

# 1. Update the configuration file using a robust awk script.
log "Updating configuration file at '${CONFIG_FILE}'..."
# Pass the model_id as an environment variable to awk to handle slashes correctly.
MODEL_ID="${MODEL_ID}" awk '
    BEGIN { in_section=0; updated=0; model_id=ENVIRON["MODEL_ID"] }
    /\[services\.chat\]/ { in_section=1 }
    /^\s*\[.*\]/ && !/\[services\.chat\]/ { in_section=0 }
    in_section && /^\s*model\s*=/ {
        print "  model = \"" model_id "\""
        updated=1
        next
    }
    { print }
    END { if (updated==0) { print "[ERROR] 'model =' key not found under [services.chat] section." > "/dev/stderr"; exit 1 } }
' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
success "Configuration updated."

# 2. Restart the chat service to apply the changes.
log "Restarting chat service ('${SERVICE_NAME}')..."
sudo launchctl kickstart -k "system/${SERVICE_NAME}"
success "Service restarted. Download should begin shortly."

# 3. Monitor the log file for download progress.
REAL_USER=${SUDO_USER:-$(whoami)}
LOG_FILE="/Users/${REAL_USER}/Library/Logs/${SERVICE_NAME}/stderr.log"
LOG_DIR=$(dirname "${LOG_FILE}")

log "Tailing log file to monitor download progress..."
echo "   Log file: ${LOG_FILE}"
echo "   (Press Ctrl+C to stop monitoring)"

# Ensure the log directory exists before trying to access the file.
mkdir -p "${LOG_DIR}"
# Give the service a moment to start and clear the old log.
sleep 2
# Clear the log file so we only see the new download progress.
> "$LOG_FILE"

# Use awk to process the log file in real-time and display a progress bar.
tail -f "$LOG_FILE" | awk '
    # Look for the huggingface_hub progress line (e.g., "Fetching 1.34/4.95 GB [...]")
    /Fetching/ && /GB/ {
        # Extract the downloaded and total size
        match($0, /([0-9\.]+)\/([0-9\.]+) GB/, parts)
        downloaded = parts[1]
        total = parts[2]
        percent = int(downloaded / total * 100)

        # Extract the speed/ETA part of the line
        match($0, /\[.*<.*,.*\/s\]/, eta_parts)
        eta_str = eta_parts[0]

        width = 50
        filled = int(width * percent / 100)
        bar = ""
        for (i = 0; i < filled; i++) bar = bar "█"
        for (i = width - filled; i > 0; i--) bar = bar " "

        printf "\rDownloading... %3d%% |%s| %s / %s GB %s", percent, bar, downloaded, total, eta_str
    }
    # Look for the final "Model loaded" message from the chat server
    /Model .* loaded/ {
        print "\n" # Newline to preserve the progress bar
        print "✅ [MODEL-UPDATER] Model loaded successfully!"
        # Exit the awk script, which will terminate the tail pipe
        exit 0
    }
'

# In case the awk script exits for any reason, print a final message.
echo ""
success "Monitoring complete."
