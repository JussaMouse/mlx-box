#!/bin/bash

# Install Startup Services for Local AI Models
# Run with: sudo ./install-startup-services.sh

set -e

echo "🚀 Installing Local AI Model Startup Services"
echo "=============================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root: sudo ./install-startup-services.sh"
    exit 1
fi

# Get the current user (the one who called sudo)
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME="/Users/$REAL_USER"
# Dynamically determine the project directory based on this script's location
PROJECT_DIR=$(dirname "$0")

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
    # Fallback for non-interactive shells where .zshrc might not be sourced
    if [ -f "$USER_HOME/.local/bin/poetry" ]; then
        POETRY_PATH="$USER_HOME/.local/bin/poetry"
    else
        echo "❌ Poetry not found. Please ensure Poetry is installed and in your PATH."
        exit 1
    fi
fi
echo "📦 Poetry: $POETRY_PATH"

# Create log directory
mkdir -p /var/log
touch /var/log/mlx-chat-server.log
touch /var/log/mlx-chat-server-error.log
touch /var/log/embed-server.log
touch /var/log/embed-server-error.log

# Set log permissions
chown $REAL_USER:staff /var/log/mlx-chat-server*.log
chown $REAL_USER:staff /var/log/embed-server*.log

echo "📝 Creating LaunchDaemon plist files..."

# Ensure server files exist
if [ ! -f "$PROJECT_DIR/chat-server.py" ]; then
    echo "❌ Chat server script not found: $PROJECT_DIR/chat-server.py"
    exit 1
fi
if [ ! -f "$PROJECT_DIR/embed-server.py" ]; then
    echo "❌ Embed server script not found: $PROJECT_DIR/embed-server.py"
    exit 1
fi

# Create Chat Server plist
cat > /Library/LaunchDaemons/com.local.mlx-chat-server.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.mlx-chat-server</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>$POETRY_PATH</string>
        <string>run</string>
        <string>python3</string>
        <string>chat-server.py</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/var/log/mlx-chat-server.log</string>
    
    <key>StandardErrorPath</key>
    <string>/var/log/mlx-chat-server-error.log</string>
    
    <key>UserName</key>
    <string>$REAL_USER</string>
    
    <key>GroupName</key>
    <string>staff</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "$POETRY_PATH"):/opt/homebrew/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$USER_HOME</string>
    </dict>
    
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

# Create Embedding Server plist
cat > /Library/LaunchDaemons/com.local.embed-server.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.embed-server</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>$POETRY_PATH</string>
        <string>run</string>
        <string>python3</string>
        <string>embed-server.py</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/var/log/embed-server.log</string>
    
    <key>StandardErrorPath</key>
    <string>/var/log/embed-server-error.log</string>
    
    <key>UserName</key>
    <string>$REAL_USER</string>
    
    <key>GroupName</key>
    <string>staff</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "$POETRY_PATH"):/opt/homebrew/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$USER_HOME</string>
    </dict>
    
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

# Set proper permissions
chmod 644 /Library/LaunchDaemons/com.local.*.plist
chown root:wheel /Library/LaunchDaemons/com.local.*.plist

echo "✅ LaunchDaemon files created"

# Load the services
echo "🔄 Loading services using modern bootstrap method..."

# Unload any old versions that might be stuck
launchctl bootout system /Library/LaunchDaemons/com.local.embed-server.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-chat-server.plist 2>/dev/null || true

echo "Starting embedding server first (lighter load)..."
launchctl bootstrap system /Library/LaunchDaemons/com.local.embed-server.plist
launchctl kickstart -k system/com.local.embed-server

echo "Waiting 30 seconds before starting chat server..."
sleep 30

echo "Starting chat server (heavier load)..."
launchctl bootstrap system /Library/LaunchDaemons/com.local.mlx-chat-server.plist
launchctl kickstart -k system/com.local.mlx-chat-server

echo ""
echo "🎉 Services installed and loaded!"
echo ""
echo "📊 Current Status:"
launchctl list | grep com.local || true

echo ""
echo "📖 See startup-services-management.md for:"
echo "• Log monitoring commands"
echo "• Service management (start/stop/restart)"
echo "• Test endpoints and troubleshooting"
echo ""
echo "🔗 Quick test (in ~2-5 minutes):"
echo "• http://127.0.0.1:8081/v1/models (embed)"
echo "• http://127.0.0.1:8080/v1/models (chat)" 
