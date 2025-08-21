#!/bin/bash
set -e

# --- Configuration ---
TARGET_DIR="/Users/env/server/frontend"
SERVICE_NAME="com.vice.frontend-server"
PORT=8000
NODE_PATH="/Users/env/.nvm/versions/node/v24.2.0/bin/node"
NPX_PATH="/Users/env/.nvm/versions/node/v24.2.0/bin/npx"
# --- End Configuration ---

if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root. Please use sudo:"
  echo "   sudo $0"
  exit 1
fi

REAL_USER=${SUDO_USER:-$(whoami)}
PLIST_DIR="/Library/LaunchDaemons"
PLIST_FILE="$PLIST_DIR/$SERVICE_NAME.plist"
LOG_DIR="$HOME/Library/Logs/$SERVICE_NAME"
SOURCE_DIR=$(pwd)

echo "🚀 Installing frontend as a system-wide service (using Node.js)..."

if ! command -v $NPX_PATH &> /dev/null; then
    echo "❌ Error: npx not found at $NPX_PATH"
    exit 1
fi
echo "✅ npx is available."

echo "🖥️  Ensuring frontend files are in $TARGET_DIR..."
if [ "$SOURCE_DIR" != "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
    cp -R "${SOURCE_DIR}/" "$TARGET_DIR/"
    echo "    ✅ Frontend files copied successfully."
else
    echo "    -> Already in target directory. Skipping file copy."
fi

echo "🪵  Ensuring log directory exists at $LOG_DIR..."
mkdir -p "$LOG_DIR"
chown "$REAL_USER" "$LOG_DIR"
touch "${LOG_DIR}/stdout.log" "${LOG_DIR}/stderr.log"
chmod 644 "${LOG_DIR}/stdout.log" "${LOG_DIR}/stderr.log"
echo "    ✅ Log directory is ready."

echo "🔒 Updating firewall rule for Node.js..."
/usr/libexec/ApplicationFirewall/socketfilterfw --remove /opt/homebrew/bin/python3 > /dev/null 2>&1 || true
/usr/libexec/ApplicationFirewall/socketfilterfw --add $NODE_PATH > /dev/null 2>&1 || true
/usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp $NODE_PATH > /dev/null 2>&1 || true
echo "    ✅ Firewall rule is in place for Node.js."

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
        <string>0.0.0.0</string>
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
        <string>/Users/env/.nvm/versions/node/v24.2.0/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
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
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE"

sleep 2
if curl -s --head http://localhost:${PORT} > /dev/null; then
    echo ""
    echo "🎉 Success! The frontend service is now running."
    echo "🔗 Open http://<server-ip>:${PORT} in your browser."
    echo ""
    echo "---"
    echo "To manage the service:"
    echo "  - Stop:    sudo launchctl unload '${PLIST_FILE}'"
    echo "  - Start:   sudo launchctl load '${PLIST_FILE}'"
    echo "---"
else
    echo "❌ Error: Failed to start the frontend service."
    echo "Please check the logs for more details: ${LOG_DIR}/stderr.log"
    exit 1
fi

echo "✅ Installation complete." 