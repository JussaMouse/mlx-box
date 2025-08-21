#!/bin/bash
set -e

# --- Helper Functions ---

# A function to read values from the TOML config file.
# This ensures consistency with the main installer.
read_toml() {
    local key=$1
    local config_file
    config_file=$(dirname "$0")/../config/settings.toml
    if [ ! -f "$config_file" ]; then
        echo "❌ ERROR: Configuration file not found at ${config_file}" >&2
        exit 1
    fi
    grep "^${key/./\.}" "$config_file" | cut -d'=' -f2 | tr -d ' "'
}

# --- Configuration: Read from TOML ---

# Use the absolute path to the project root to find the config file
SERVICE_NAME="com.mlx-box.frontend-server"
PORT=$(read_toml "services.frontend.port")
TARGET_DIR=$(dirname "$0") # The directory where this script is located.

# Dynamically find Node.js and npx executables.
# This is more robust than hardcoding paths.
if ! NVM_DIR="$HOME/.nvm" [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; then
    echo "❌ ERROR: Could not source nvm.sh. Is NVM installed correctly?" >&2
    exit 1
fi
NODE_PATH=$(which node)
NPX_PATH=$(which npx)

if [ -z "$NODE_PATH" ] || [ -z "$NPX_PATH" ]; then
    echo "❌ ERROR: Could not find 'node' or 'npx' in the PATH after sourcing NVM." >&2
    exit 1
fi
# --- End Configuration ---

if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root. Please use sudo:"
  echo "   sudo $0"
  exit 1
fi

REAL_USER=${SUDO_USER:-$(whoami)}
PLIST_DIR="/Library/LaunchDaemons"
PLIST_FILE="$PLIST_DIR/$SERVICE_NAME.plist"
LOG_DIR="/Users/$REAL_USER/Library/Logs/$SERVICE_NAME" # Changed to a user-specific log dir
SOURCE_DIR=$(pwd)

echo "🚀 Installing frontend as a system-wide service..."
echo "   - Port: ${PORT}"
echo "   - Target Dir: ${TARGET_DIR}"
echo "   - Node Path: ${NODE_PATH}"

# (Removed file copy section as the service now runs directly from the project dir)

echo "🪵  Ensuring log directory exists at $LOG_DIR..."
mkdir -p "$LOG_DIR"
chown "$REAL_USER" "$LOG_DIR"
touch "${LOG_DIR}/stdout.log" "${LOG_DIR}/stderr.log"
chmod 644 "${LOG_DIR}/stdout.log" "${LOG_DIR}/stderr.log"
echo "    ✅ Log directory is ready."

# (Firewall section removed - this is now handled by the main installer and pf.conf)

echo "📝 Creating LaunchDaemon service file at $PLIST_FILE..."

cat > "$PLIST_FILE" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NPX_PATH}</string>
        <string>http-server</string>
        <string>.</string>
        <string>-p</string>
        <string>${PORT}</string>
        <string>-a</string>
        <string>127.0.0.1</string> <!-- Bind to localhost for reverse proxy -->
        <string>--no-cache</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>WorkingDirectory</key>
    <string>${TARGET_DIR}</string>
    <key>UserName</key>
    <string>${REAL_USER}</string>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "${NODE_PATH}"):/opt/homebrew/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/${REAL_USER}</string>
    </dict>
</dict>
</plist>
EOL

echo "✅ Service file created."

chown root:wheel "$PLIST_FILE"
chmod 644 "$PLIST_FILE"

echo "🔄 Loading service..."
# Use bootout/bootstrap for modern, reliable service loading
sudo launchctl bootout system "$PLIST_FILE" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST_FILE"

sleep 2
if curl -s --head http://127.0.0.1:${PORT} > /dev/null; then
    echo ""
    echo "🎉 Success! The frontend service is now running on localhost:${PORT}."
    echo "   It will be served publicly by the Nginx reverse proxy."
    echo ""
else
    echo "❌ Error: Failed to start the frontend service."
    echo "   Please check the logs for more details: ${LOG_DIR}/stderr.log"
    exit 1
fi

echo "✅ Installation complete." 