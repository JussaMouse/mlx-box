#!/bin/bash

# Install Startup Services for Local AI Models (3-Tier Architecture with Auth Proxies)
# Run with: sudo ./install-startup-services.sh

set -e

echo "🚀 Installing Local AI Model Startup Services (3-Tier with Auth Proxies)"
echo "========================================================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root: sudo ./startup-services-install.sh"
    exit 1
fi

# Get the current user (the one who called sudo)
REAL_USER=${SUDO_USER:-$(whoami)}
USER_HOME="/Users/$REAL_USER"
# Dynamically determine the absolute path to the project directory.
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG_DIR="$PROJECT_DIR/../config"

echo "👤 User: $REAL_USER"
echo "🏠 Home: $USER_HOME"
echo "📁 Project: $PROJECT_DIR"
echo "⚙️  Config: $CONFIG_DIR"

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Project directory not found: $PROJECT_DIR"
    exit 1
fi

# Check if settings.toml exists
if [ ! -f "$CONFIG_DIR/settings.toml" ]; then
    echo "❌ Configuration file not found: $CONFIG_DIR/settings.toml"
    echo "   Please copy settings.toml.example to settings.toml and configure it"
    exit 1
fi

# Dynamically find the poetry executable (works for common install paths)
if ! POETRY_PATH=$(which poetry 2>/dev/null); then
    if [ -x "$USER_HOME/.local/bin/poetry" ]; then
        POETRY_PATH="$USER_HOME/.local/bin/poetry"
    elif [ -x "$USER_HOME/Library/Python/3.9/bin/poetry" ]; then
        POETRY_PATH="$USER_HOME/Library/Python/3.9/bin/poetry"
    elif [ -x "/opt/homebrew/bin/poetry" ]; then
        POETRY_PATH="/opt/homebrew/bin/poetry"
    else
        echo "❌ Poetry not found. Please ensure Poetry is installed and in your PATH."
        exit 1
    fi
fi
echo "📦 Poetry: $POETRY_PATH"

# --- Python/Poetry environment hardening ---
BREW_BIN=""
if [ -x "/opt/homebrew/bin/brew" ]; then
    BREW_BIN="/opt/homebrew/bin/brew"
elif command -v brew >/dev/null 2>&1; then
    BREW_BIN="$(command -v brew)"
fi

USER_ENV_PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$USER_HOME/.local/bin"

run_as_user() {
    sudo -u "$REAL_USER" -H env HOME="$USER_HOME" PATH="$USER_ENV_PATH" "$@"
}

if [ -z "$BREW_BIN" ]; then
    echo "❌ Homebrew not found. Required to install python@3.12 for OCR."
    exit 1
fi

PY312="/opt/homebrew/bin/python3.12"
if [ ! -x "$PY312" ]; then
    echo "📦 Installing Homebrew python@3.12 (required for OCR dependencies)..."
    run_as_user "$BREW_BIN" install python@3.12
fi

echo "🔧 Ensuring Poetry uses Python 3.12 for this project..."
run_as_user bash -lc "cd \"$PROJECT_DIR\" && \"$POETRY_PATH\" env use \"$PY312\""
echo "📦 Installing/updating Python deps (poetry install)..."
run_as_user bash -lc "cd \"$PROJECT_DIR\" && \"$POETRY_PATH\" install --no-interaction --no-root"

# Create log directories for all services (both backend and frontend)
LOG_BASE="$USER_HOME/Library/Logs"
SERVICES=(
    "com.mlx-box.router-backend"
    "com.mlx-box.router"
    "com.mlx-box.fast-backend"
    "com.mlx-box.fast"
    "com.mlx-box.thinking-backend"
    "com.mlx-box.thinking"
    "com.mlx-box.embedding-backend"
    "com.mlx-box.embedding"
    "com.mlx-box.ocr-backend"
    "com.mlx-box.ocr"
)

for service in "${SERVICES[@]}"; do
    mkdir -p "$LOG_BASE/$service"
    chown -R "$REAL_USER" "$LOG_BASE/$service"
done

echo "📝 Creating LaunchDaemon files..."

# Ensure /usr/local/bin exists
sudo mkdir -p /usr/local/bin
sudo chown root:wheel /usr/local/bin || true

# Helper function to create Backend MLX Service Launchers
create_backend_launcher() {
    local NAME=$1
    local SERVICE_ARG=$2
    local LAUNCHER_PATH="/usr/local/bin/mlx-${NAME}-backend-launcher.sh"

    sudo tee "$LAUNCHER_PATH" > /dev/null << SH
#!/bin/bash
export HOME="$USER_HOME"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$USER_HOME/.local/bin"
cd "$PROJECT_DIR" || exit 1
exec "$POETRY_PATH" run python3 chat-server.py --service $SERVICE_ARG
SH
    sudo chmod 755 "$LAUNCHER_PATH"
    sudo chown root:wheel "$LAUNCHER_PATH"
    echo "  Created backend launcher: $LAUNCHER_PATH"
}

# Helper function to create Frontend Auth Proxy Launchers
create_frontend_launcher() {
    local SERVICE=$1
    local FRONTEND_PORT=$2
    local BACKEND_PORT=$3
    local LAUNCHER_PATH="/usr/local/bin/mlx-${SERVICE}-auth-launcher.sh"

    sudo tee "$LAUNCHER_PATH" > /dev/null << SH
#!/bin/bash
export HOME="$USER_HOME"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$USER_HOME/.local/bin"
cd "$PROJECT_DIR" || exit 1
exec "$POETRY_PATH" run python3 auth-proxy.py \\
    --service $SERVICE \\
    --frontend-port $FRONTEND_PORT \\
    --backend-port $BACKEND_PORT
SH
    sudo chmod 755 "$LAUNCHER_PATH"
    sudo chown root:wheel "$LAUNCHER_PATH"
    echo "  Created auth proxy launcher: $LAUNCHER_PATH"
}

echo "🔧 Creating Backend MLX Service Launchers..."
create_backend_launcher "router" "router"
create_backend_launcher "fast" "fast"
create_backend_launcher "thinking" "thinking"

# Embed backend launcher
EMBED_BACKEND_LAUNCHER="/usr/local/bin/mlx-embedding-backend-launcher.sh"
sudo tee "$EMBED_BACKEND_LAUNCHER" > /dev/null << SH
#!/bin/bash
export HOME="$USER_HOME"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$USER_HOME/.local/bin"
cd "$PROJECT_DIR" || exit 1
exec "$POETRY_PATH" run python3 embed-server.py
SH
sudo chmod 755 "$EMBED_BACKEND_LAUNCHER"
sudo chown root:wheel "$EMBED_BACKEND_LAUNCHER"
echo "  Created backend launcher: $EMBED_BACKEND_LAUNCHER"

# OCR backend launcher
OCR_BACKEND_LAUNCHER="/usr/local/bin/mlx-ocr-backend-launcher.sh"
sudo tee "$OCR_BACKEND_LAUNCHER" > /dev/null << SH
#!/bin/bash
export HOME="$USER_HOME"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$USER_HOME/.local/bin"
cd "$PROJECT_DIR" || exit 1
exec "$POETRY_PATH" run python3 ocr-server.py
SH
sudo chmod 755 "$OCR_BACKEND_LAUNCHER"
sudo chown root:wheel "$OCR_BACKEND_LAUNCHER"
echo "  Created backend launcher: $OCR_BACKEND_LAUNCHER"

echo "🔧 Reading port configuration from settings.toml..."
# Parse ports from settings.toml using Python via Poetry
PARSE_CMD="import tomlkit; c = tomlkit.load(open('$CONFIG_DIR/settings.toml'))"

read -r ROUTER_PORT ROUTER_BACKEND < <(run_as_user bash -lc "cd '$PROJECT_DIR' && '$POETRY_PATH' run python3 -c \"$PARSE_CMD; print(c['services']['router'].get('port', 8082), c['services']['router'].get('backend_port', 8092))\"")

read -r FAST_PORT FAST_BACKEND < <(run_as_user bash -lc "cd '$PROJECT_DIR' && '$POETRY_PATH' run python3 -c \"$PARSE_CMD; print(c['services']['fast'].get('port', 8080), c['services']['fast'].get('backend_port', 8090))\"")

read -r THINKING_PORT THINKING_BACKEND < <(run_as_user bash -lc "cd '$PROJECT_DIR' && '$POETRY_PATH' run python3 -c \"$PARSE_CMD; print(c['services']['thinking'].get('port', 8081), c['services']['thinking'].get('backend_port', 8091))\"")

read -r EMBEDDING_PORT EMBEDDING_BACKEND < <(run_as_user bash -lc "cd '$PROJECT_DIR' && '$POETRY_PATH' run python3 -c \"$PARSE_CMD; print(c['services']['embedding'].get('port', 8083), c['services']['embedding'].get('backend_port', 8093))\"")

read -r OCR_PORT OCR_BACKEND < <(run_as_user bash -lc "cd '$PROJECT_DIR' && '$POETRY_PATH' run python3 -c \"$PARSE_CMD; print(c['services']['ocr'].get('port', 8085), c['services']['ocr'].get('backend_port', 8095))\"")

echo "  Router: frontend=$ROUTER_PORT, backend=$ROUTER_BACKEND"
echo "  Fast: frontend=$FAST_PORT, backend=$FAST_BACKEND"
echo "  Thinking: frontend=$THINKING_PORT, backend=$THINKING_BACKEND"
echo "  Embedding: frontend=$EMBEDDING_PORT, backend=$EMBEDDING_BACKEND"
echo "  OCR: frontend=$OCR_PORT, backend=$OCR_BACKEND"

echo "🔧 Creating Frontend Auth Proxy Launchers..."
create_frontend_launcher "router" $ROUTER_PORT $ROUTER_BACKEND
create_frontend_launcher "fast" $FAST_PORT $FAST_BACKEND
create_frontend_launcher "thinking" $THINKING_PORT $THINKING_BACKEND
create_frontend_launcher "embedding" $EMBEDDING_PORT $EMBEDDING_BACKEND
create_frontend_launcher "ocr" $OCR_PORT $OCR_BACKEND

# Helper function to create Backend MLX Service Plists
create_backend_plist() {
    local NAME=$1
    local PLIST_NAME="com.mlx-box.${NAME}-backend"
    local LAUNCHER_PATH="/usr/local/bin/mlx-${NAME}-backend-launcher.sh"

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

# Helper function to create Frontend Auth Proxy Plists
create_frontend_plist() {
    local NAME=$1
    local PLIST_NAME="com.mlx-box.${NAME}"
    local LAUNCHER_PATH="/usr/local/bin/mlx-${NAME}-auth-launcher.sh"

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

echo "📝 Creating Backend MLX Service Plists..."
create_backend_plist "router"
create_backend_plist "fast"
create_backend_plist "thinking"
create_backend_plist "embedding"
create_backend_plist "ocr"

echo "📝 Creating Frontend Auth Proxy Plists..."
create_frontend_plist "router"
create_frontend_plist "fast"
create_frontend_plist "thinking"
create_frontend_plist "embedding"
create_frontend_plist "ocr"

# Permissions
chmod 644 /Library/LaunchDaemons/com.mlx-box.*.plist
chown root:wheel /Library/LaunchDaemons/com.mlx-box.*.plist

echo "✅ LaunchDaemon files created"

# Cleanup old services
echo "🧹 Cleaning up legacy services..."
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-chat-server.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-router.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-fast.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.mlx-thinking.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.embed-server.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.local.ocr-server.plist 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.local.mlx-*.plist
rm -f /Library/LaunchDaemons/com.local.embed-server.plist
rm -f /Library/LaunchDaemons/com.local.ocr-server.plist

# Bootout any existing new services
echo "🔄 Stopping existing services..."
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.router-backend.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.router.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.fast-backend.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.fast.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.thinking-backend.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.thinking.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.embedding-backend.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.embedding.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.ocr-backend.plist 2>/dev/null || true
launchctl bootout system /Library/LaunchDaemons/com.mlx-box.ocr.plist 2>/dev/null || true

# Start Backend services first (they must be running before auth proxies)
echo "🚀 Starting Backend MLX Services..."
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.embedding-backend.plist
sleep 2
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.ocr-backend.plist
sleep 2
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.router-backend.plist
sleep 2
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.fast-backend.plist
sleep 2
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.thinking-backend.plist

# Give backends time to start
echo "⏳ Waiting for backend services to initialize..."
sleep 5

# Start Frontend auth proxies
echo "🚀 Starting Frontend Auth Proxy Services..."
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.embedding.plist
sleep 1
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.ocr.plist
sleep 1
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.router.plist
sleep 1
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.fast.plist
sleep 1
launchctl bootstrap system /Library/LaunchDaemons/com.mlx-box.thinking.plist

echo ""
echo "🎉 All services installed and loaded!"
echo "📊 Service Status:"
launchctl list | grep com.mlx-box || true

echo ""
echo "🔐 Auth Proxy Architecture:"
echo "  Frontend (auth): router=$ROUTER_PORT, fast=$FAST_PORT, thinking=$THINKING_PORT, embedding=$EMBEDDING_PORT, ocr=$OCR_PORT"
echo "  Backend (MLX):   router=$ROUTER_BACKEND, fast=$FAST_BACKEND, thinking=$THINKING_BACKEND, embedding=$EMBEDDING_BACKEND, ocr=$OCR_BACKEND"
echo ""
echo "Check logs to verify authentication is enabled:"
echo "  tail ~/Library/Logs/com.mlx-box.fast/stderr.log"
echo ""
