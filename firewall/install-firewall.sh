#!/bin/bash
set -e

# This script must be run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root. Please use sudo."
  exit 1
fi

echo "🚀 Starting custom firewall configuration..."

# 1. Copy pf configuration file
echo "📝 Copying pf.conf to /etc/pf.conf..."
cp "$(dirname "$0")/pf.conf" /etc/pf.conf
chown root:wheel /etc/pf.conf
chmod 644 /etc/pf.conf
echo "    ✅ pf.conf copied."

# 2. Create and load LaunchDaemon for pf
PLIST_PATH="/Library/LaunchDaemons/com.local.firewall.plist"
echo "📝 Creating LaunchDaemon at $PLIST_PATH..."

cat > "$PLIST_PATH" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.firewall</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/pfctl</string>
        <string>-f</string>
        <string>/etc/pf.conf</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/pf-firewall.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/pf-firewall.log</string>
</dict>
</plist>
EOL
chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"
echo "    ✅ LaunchDaemon created."

# 3. Disable the built-in Application Firewall
echo "🔒 Disabling built-in macOS Application Firewall..."
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
echo "    ✅ Application Firewall disabled."

# 4. Load the new pf firewall service
echo "🔄 Loading and enabling new 'pf' firewall service..."
# Unload any old version first
launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
# Load the new service
launchctl bootstrap system "$PLIST_PATH"
# Enable pf
pfctl -E
echo "    ✅ 'pf' firewall is now active and will load on boot."

echo ""
echo "🎉 Custom firewall installation complete."
echo "pf.conf installed. Allowed inbound ports are defined in $(dirname "$0")/pf.conf."
echo "All other incoming ports are blocked by default."