#!/bin/bash

# Install Startup Services for Local AI Models (3-Tier Architecture)
# Run with: sudo ./install-startup-services.sh

set -e

echo "🚀 Installing Local AI Model Startup Services (3-Tier)"
echo "===================================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root: sudo ./install-startup-services.sh"
    exit 1
fi

# Get the current user (the one who called sudo)
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME="/Users/$REAL_USER"
# Dynamically determine the absolute path to the project directory.
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "👤 User: $REAL_USER"
echo "🏠 Home: $USER_HOME"
echo "📁 Project: $PROJECT_DIR"

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Project directory not found: $PROJECT_DIR"
    exit 1
fi

# Dynamically find the poetry executable
if ! POETRY_PATH=$(which poetry); then
    if [ -f "$USER_HOME/.local/bin/poetry" ]; then
        POETRY_PATH="$USER_HOME/.local/bin/poetry"
    else
        echo "❌ Poetry not found. Please ensure Poetry is installed and in your PATH."
        exit 1
    fi
fi
echo "📦 Poetry: $POETRY_PATH"

# Create log directories for all 4 services
LOG_BASE="$USER_HOME/Library/Logs"
SERVICES=(
    "com.local.mlx-router" 
    "com.local.mlx-fast" 
    "com.local.mlx-thinking" 
    "com.local.embed-server"
)

for service in "${SERVICES[@]}"; do
    mkdir -p "$LOG_BASE/$service"
    chown -R "$REAL_USER" "$LOG_BASE/$service"
done

echo "📝 Creating LaunchDaemon plist files..."

# Ensure /usr/local/bin exists
sudo mkdir -p /usr/local/bin
sudo chown root:wheel /usr/local/bin || true

# Helper function to create Chat Launchers
create_launcher() {
    local NAME=$1
    local SERVICE_ARG=$2
    local LAUNCHER_PATH="/usr/local/bin/mlx-${NAME}-launcher.sh"
    
    # We need to find the VENV path. This is tricky as root.
    # We'll use a hack to ask poetry where the venv is as the user.
    # For now, we rely on the install script running `poetry install` previously.
    # Note: In the previous script, VENV_PY was hardcoded or assumed. 
    # Here we will try to make the launcher robust by cd-ing and running poetry run.
    
    sudo tee "$LAUNCHER_PATH" > /dev/null << SH
#!/bin/bash
export HOME="$USER_HOME"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$USER_HOME/.local/bin"

# Navigate to project dir
cd "$PROJECT_DIR" || exit 1

# Execute via poetry using the specific service argument
exec "$POETRY_PATH" run python3 chat-server.py --service $SERVICE_ARG
SH
    sudo chmod 755 "$LAUNCHER_PATH"
    sudo chown root:wheel "$LAUNCHER_PATH"
    echo "Created launcher: $LAUNCHER_PATH"
}

create_launcher "router" "router"
create_launcher "fast" "fast"
create_launcher "thinking" "thinking"

# Embed launcher is slightly different (different script)
EMBED_LAUNCHER="/usr/local/bin/mlx-embed-launcher.sh"
sudo tee "$EMBED_LAUNCHER" > /dev/null << SH
#!/bin/bash
export HOME="$USER_HOME"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$USER_HOME/.local/bin"
cd "$PROJECT_DIR" || exit 1
exec "$POETRY_PATH" run python3 embed-server.py
SH
sudo chmod 755 "$EMBED_LAUNCHER"
sudo chown root:wheel "$EMBED_LAUNCHER"

# Helper function to create Chat Plists
create_chat_plist() {
    local NAME=$1
    local PLIST_NAME="com.local.mlx-${NAME}"
    local LAUNCHER_PATH="/usr/local/bin/mlx-${NAME}-launcher.sh"
    
    cat > "/Library/LaunchDaemons/${PLIST_NAME}.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>${LAUNCHER_PATH}</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>${LOG_BASE}/${PLIST_NAME}/stdout.log</string>
    
    <key>StandardErrorPath</key>
    <string>${LOG_BASE}/${PLIST_NAME}/stderr.log</string>
    
    <key>UserName</key>
    <string>$REAL_USER</string>
    
    <key>GroupName</key>
    <string>staff</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>$USER_HOME</string>
    </dict>
</dict>
</plist>
EOF
}

create_chat_plist "router"
create_chat_plist "fast"
create_chat_plist "thinking"

# Embed Plist
cat > /Library/LaunchDaemons/com.local.embed-server.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.embed-server</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/mlx-embed-launcher.sh</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>${LOG_BASE}/com.local.embed-server/stdout.log</string>
    
    <key>StandardErrorPath</key>
    <string>${LOG_BASE}/com.local.embed-server/stderr.log</string>
    
    <key>UserName</key>
    <string>$REAL_USER</string>
    
    <key>GroupName</key>
    <string>staff</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>$USER_HOME</string>
    </dict>
</dict>
</plist>
EOF

# Permissions
chmod 644 /Library/LaunchDaemons/com.local.*.plist
chown root:wheel /Library/LaunchDaemons/com.local.*.plist

echo "✅ LaunchDaemon files created"

# Cleanup old single-chat service if it exists
echo "🧹 Cleaning up legacy services..."
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-chat-server.plist 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.local.mlx-chat-server.plist

# Load new services
echo "🔄 Loading 3-Tier services..."

# Bootout existing new services to ensure clean reload
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-router.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-fast.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-thinking.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.embed-server.plist 2>/dev/null || true

# Start them (Embedding first)
launchctl bootstrap system /Library/LaunchDaemons/com.local.embed-server.plist

# Start Router
launchctl bootstrap system /Library/LaunchDaemons/com.local.mlx-router.plist

# Start Fast & Thinking (staggered slightly to avoid IO spike)
sleep 2
launchctl bootstrap system /Library/LaunchDaemons/com.local.mlx-fast.plist
sleep 2
launchctl bootstrap system /Library/LaunchDaemons/com.local.mlx-thinking.plist

echo ""
echo "🎉 All services installed and loaded!"
echo "📊 Service Status:"
launchctl list | grep com.local || true

echo ""
echo "Please verify your endpoints match your config/settings.toml"
