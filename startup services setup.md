# 🚀 Automatic Startup Services for Local AI Models

Setup chat and embedding servers to automatically start when your Mac boots up.

## 📋 Overview

This setup creates macOS LaunchDaemons that will:
- Start `chat_server.py` on system boot (Port 8080)
- Start `embed-server.py` on system boot (Port 8081)
- Automatically restart if they crash
- Run with proper logging

## 🛠️ Prerequisites

- Working `chat_server.py` and `embed-server.py` 
- Poetry environment set up
- Admin privileges on your Mac

## 📄 Service Configuration Files

### 1. Chat Server LaunchDaemon

Create `/Library/LaunchDaemons/com.local.mlx-chat-server.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.mlx-chat-server</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/poetry</string>
        <string>run</string>
        <string>python</string>
        <string>chat_server.py</string>
        <string>4bit</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>/Users/lon/projects/local-model</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/var/log/mlx-chat-server.log</string>
    
    <key>StandardErrorPath</key>
    <string>/var/log/mlx-chat-server-error.log</string>
    
    <key>UserName</key>
    <string>lon</string>
    
    <key>GroupName</key>
    <string>staff</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/lon</string>
    </dict>
    
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
```

### 2. Embedding Server LaunchDaemon

Create `/Library/LaunchDaemons/com.local.embed-server.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.embed-server</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/poetry</string>
        <string>run</string>
        <string>python</string>
        <string>embed-server.py</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>/Users/lon/projects/local-model</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/var/log/embed-server.log</string>
    
    <key>StandardErrorPath</key>
    <string>/var/log/embed-server-error.log</string>
    
    <key>UserName</key>
    <string>lon</string>
    
    <key>GroupName</key>
    <string>staff</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/lon</string>
    </dict>
    
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
```

## 🔧 Installation Script

Create `install-startup-services.sh`:

```bash
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
PROJECT_DIR="$USER_HOME/projects/local-model"

echo "👤 User: $REAL_USER"
echo "🏠 Home: $USER_HOME"
echo "📁 Project: $PROJECT_DIR"

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Project directory not found: $PROJECT_DIR"
    exit 1
fi

# Check if Poetry is installed
if ! command -v poetry &> /dev/null; then
    echo "❌ Poetry not found. Please install Poetry first."
    exit 1
fi

POETRY_PATH=$(which poetry)
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
        <string>python</string>
        <string>chat_server.py</string>
        <string>4bit</string>
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
        <string>/usr/local/bin:/usr/bin:/bin</string>
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
        <string>python</string>
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
        <string>/usr/local/bin:/usr/bin:/bin</string>
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
echo "🔄 Loading services..."
launchctl load /Library/LaunchDaemons/com.local.embed-server.plist
launchctl load /Library/LaunchDaemons/com.local.mlx-chat-server.plist

echo ""
echo "🎉 Services installed and loaded!"
echo ""
echo "📊 Service Status:"
launchctl list | grep com.local || true

echo ""
echo "📋 Management Commands:"
echo "• View logs: tail -f /var/log/embed-server.log"
echo "• View chat logs: tail -f /var/log/mlx-chat-server.log"
echo "• Stop embed: sudo launchctl unload /Library/LaunchDaemons/com.local.embed-server.plist"
echo "• Stop chat: sudo launchctl unload /Library/LaunchDaemons/com.local.mlx-chat-server.plist"
echo "• Start embed: sudo launchctl load /Library/LaunchDaemons/com.local.embed-server.plist"
echo "• Start chat: sudo launchctl load /Library/LaunchDaemons/com.local.mlx-chat-server.plist"
echo ""
echo "🔗 Test endpoints in ~30 seconds:"
echo "• Chat: http://127.0.0.1:8080/v1/models"
echo "• Embed: http://127.0.0.1:8081/v1/models"
```

## 🚀 Installation Steps

### 1. Make script executable
```bash
chmod +x install-startup-services.sh
```

### 2. Install services
```bash
sudo ./install-startup-services.sh
```

### 3. Verify installation
```bash
# Check if services are loaded
sudo launchctl list | grep com.local

# Check logs
tail -f /var/log/embed-server.log
tail -f /var/log/mlx-chat-server.log
```

## 📊 Service Management

### Check Service Status
```bash
# List all local services
sudo launchctl list | grep com.local

# Check specific service
sudo launchctl print system/com.local.mlx-chat-server
```

### Stop Services
```bash
# Stop chat server
sudo launchctl unload /Library/LaunchDaemons/com.local.mlx-chat-server.plist

# Stop embedding server
sudo launchctl unload /Library/LaunchDaemons/com.local.embed-server.plist
```

### Start Services
```bash
# Start embedding server
sudo launchctl load /Library/LaunchDaemons/com.local.embed-server.plist

# Start chat server
sudo launchctl load /Library/LaunchDaemons/com.local.mlx-chat-server.plist
```

### Remove Services
```bash
# Unload and remove
sudo launchctl unload /Library/LaunchDaemons/com.local.embed-server.plist
sudo launchctl unload /Library/LaunchDaemons/com.local.mlx-chat-server.plist
sudo rm /Library/LaunchDaemons/com.local.*.plist
```

## 📋 Monitoring & Logs

### View Real-time Logs
```bash
# Embedding server logs
tail -f /var/log/embed-server.log

# Chat server logs  
tail -f /var/log/mlx-chat-server.log

# Error logs
tail -f /var/log/embed-server-error.log
tail -f /var/log/mlx-chat-server-error.log
```

### Log Rotation
```bash
# Create logrotate config (optional)
sudo tee /etc/newsyslog.d/ai-servers.conf << EOF
/var/log/embed-server.log    644  5  10000  *  G
/var/log/mlx-chat-server.log 644  5  10000  *  G
EOF
```

## 🧪 Testing Startup Services

### After Reboot Test
```bash
# Wait ~2-5 minutes after boot, then test:

# Test embedding server
curl http://127.0.0.1:8081/v1/models

# Test chat server
curl http://127.0.0.1:8080/v1/models

# Check if both are running
lsof -i :8080 -i :8081
```

## 🔧 Troubleshooting

### Services Won't Start
1. **Check Poetry path**: `which poetry`
2. **Check permissions**: `ls -la /Library/LaunchDaemons/com.local.*`
3. **Check logs**: `tail -f /var/log/*-server-error.log`
4. **Manual test**: `cd ~/projects/local-model && poetry run python embed-server.py`

### Memory Issues
- Services start sequentially with 10-second throttle
- Embedding server starts first (lighter load)
- Chat server starts after (heavier load)
- Consider lowering chat quantization to 4bit

### Network Conflicts
```bash
# Check what's using ports
lsof -i :8080
lsof -i :8081

# Kill conflicting processes
sudo lsof -ti:8080 | xargs kill -9
```

## ⚙️ Configuration Options

### Change Quantization
Edit `/Library/LaunchDaemons/com.local.mlx-chat-server.plist`:
```xml
<string>6bit</string>  <!-- Change from 4bit to 6bit or 8bit -->
```

Then reload:
```bash
sudo launchctl unload /Library/LaunchDaemons/com.local.mlx-chat-server.plist
sudo launchctl load /Library/LaunchDaemons/com.local.mlx-chat-server.plist
```

### Delayed Start
Add to plist for delayed startup:
```xml
<key>StartInterval</key>
<integer>60</integer>  <!-- Wait 60 seconds after boot -->
```

---

**🎉 Your AI servers will now start automatically on boot!** 