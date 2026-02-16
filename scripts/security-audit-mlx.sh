#!/usr/bin/env bash
# MLX-Box Security Audit
# Checks security posture for MLX service deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS="${GREEN}✓${NC}"
WARN="${YELLOW}⚠${NC}"
FAIL="${RED}✗${NC}"
INFO="${BLUE}ℹ${NC}"

# Determine project root
if [ -d "$(pwd)/models" ] && [ -d "$(pwd)/config" ]; then
    PROJECT_ROOT="$(pwd)"
elif [ -d "$(dirname "${BASH_SOURCE[0]}")/../models" ]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    echo "Error: Cannot find MLX-Box project root"
    echo "Please run this script from the mlx-box directory"
    exit 1
fi

cd "$PROJECT_ROOT"

echo "========================================="
echo "MLX-Box Security Audit"
echo "========================================="
echo "Project: $PROJECT_ROOT"
echo ""

ISSUES=0
WARNINGS=0

# === 1. Configuration File Security ===
echo "1. Configuration File Security"
echo "------------------------------"

CONFIG_FILE="config/settings.toml"
if [ -f "$CONFIG_FILE" ]; then
    PERMS=$(stat -f "%A" "$CONFIG_FILE" 2>/dev/null || stat -c "%a" "$CONFIG_FILE" 2>/dev/null)
    if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
        echo -e "$PASS settings.toml permissions: $PERMS (secure)"
    else
        echo -e "$WARN settings.toml permissions: $PERMS (recommended: 600)"
        echo "   Fix: chmod 600 $CONFIG_FILE"
        ((WARNINGS++))
    fi

    # Check if API key is set
    if grep -q "api_key.*=.*\"\"" "$CONFIG_FILE" 2>/dev/null || \
       grep -q "api_keys.*=.*\[\]" "$CONFIG_FILE" 2>/dev/null; then
        echo -e "$WARN No API key configured (services are unprotected)"
        echo "   Add api_key or api_keys to $CONFIG_FILE"
        ((WARNINGS++))
    else
        echo -e "$PASS API authentication configured"
    fi
else
    echo -e "$FAIL $CONFIG_FILE not found"
    ((ISSUES++))
fi

# Check for example file not renamed
if [ ! -f "$CONFIG_FILE" ] && [ -f "config/settings.toml.example" ]; then
    echo -e "$WARN Using example config - copy to settings.toml and customize"
    ((WARNINGS++))
fi

echo ""

# === 2. Network Binding ===
echo "2. Network Binding"
echo "------------------"

if [ -f "$CONFIG_FILE" ]; then
    HOST=$(grep "^host" "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
    if [ "$HOST" = "127.0.0.1" ]; then
        echo -e "$PASS host = \"127.0.0.1\" (secure - localhost only)"
    elif [ "$HOST" = "0.0.0.0" ]; then
        echo -e "$FAIL host = \"0.0.0.0\" (EXPOSED TO NETWORK!)"
        echo "   Change to \"127.0.0.1\" in $CONFIG_FILE"
        ((ISSUES++))
    else
        echo -e "$INFO host = \"$HOST\""
    fi
fi

echo ""

# === 3. Service Status ===
echo "3. MLX Services Status"
echo "----------------------"

# Check if services are running
for service in router fast thinking embedding ocr; do
    if launchctl list | grep -q "com.mlx-box.$service\$"; then
        echo -e "$PASS ${service} service: running"
    else
        echo -e "$INFO ${service} service: not running"
    fi
done

echo ""

# === 4. Log File Security ===
echo "4. Log File Security"
echo "--------------------"

LOG_DIR="$HOME/Library/Logs"
if [ -d "$LOG_DIR" ]; then
    LOG_FILES=$(find "$LOG_DIR" -name "com.mlx-box.*.log" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$LOG_FILES" -gt 0 ]; then
        echo -e "$INFO Found $LOG_FILES MLX service log files"

        # Check permissions on log files
        INSECURE_LOGS=0
        while IFS= read -r logfile; do
            PERMS=$(stat -f "%A" "$logfile" 2>/dev/null || stat -c "%a" "$logfile" 2>/dev/null)
            if [ "$PERMS" != "600" ] && [ "$PERMS" != "400" ]; then
                if [ $INSECURE_LOGS -eq 0 ]; then
                    echo -e "$WARN Some log files have loose permissions:"
                fi
                echo "   $(basename "$logfile"): $PERMS"
                ((INSECURE_LOGS++))
            fi
        done < <(find "$LOG_DIR" -name "com.mlx-box.*.log" 2>/dev/null)

        if [ $INSECURE_LOGS -eq 0 ]; then
            echo -e "$PASS All log files have secure permissions"
        else
            echo "   Fix: chmod 600 $LOG_DIR/com.mlx-box.*.log"
            ((WARNINGS++))
        fi
    else
        echo -e "$INFO No MLX log files found (services may not have been started)"
    fi
else
    echo -e "$INFO Log directory not found"
fi

echo ""

# === 5. Model Files ===
echo "5. Model File Security"
echo "----------------------"

# Check if models directory exists and is readable
if [ -d "$HOME/.cache/huggingface" ]; then
    echo -e "$PASS HuggingFace cache: $HOME/.cache/huggingface"
    CACHE_SIZE=$(du -sh "$HOME/.cache/huggingface" 2>/dev/null | cut -f1)
    echo -e "$INFO Cache size: $CACHE_SIZE"
else
    echo -e "$INFO HuggingFace cache not found (models not downloaded yet)"
fi

echo ""

# === 6. Git Security ===
echo "6. Git Security"
echo "---------------"

if [ -d .git ]; then
    if git ls-files --error-unmatch config/settings.toml >/dev/null 2>&1; then
        echo -e "$FAIL settings.toml IS TRACKED by git (contains API keys!)"
        echo "   Fix: git rm --cached config/settings.toml"
        echo "        git commit -m 'Remove settings.toml from tracking'"
        ((ISSUES++))
    else
        echo -e "$PASS settings.toml is not tracked by git"
    fi

    # Check if .gitignore exists and includes settings.toml
    if [ -f .gitignore ]; then
        if grep -q "settings.toml" .gitignore; then
            echo -e "$PASS settings.toml is in .gitignore"
        else
            echo -e "$WARN settings.toml not in .gitignore"
            echo "   Add 'settings.toml' to .gitignore"
            ((WARNINGS++))
        fi
    else
        echo -e "$WARN .gitignore not found"
        ((WARNINGS++))
    fi
else
    echo -e "$INFO Not a git repository"
fi

echo ""

# === 7. System Security ===
echo "7. System Security"
echo "------------------"

# Check FileVault (macOS)
if command -v fdesetup >/dev/null 2>&1; then
    if fdesetup status | grep -q "On"; then
        echo -e "$PASS FileVault is enabled"
    else
        echo -e "$WARN FileVault is not enabled"
        echo "   Enable in System Preferences > Security & Privacy"
        ((WARNINGS++))
    fi
fi

# Check SSH configuration
if [ -f "$HOME/.ssh/config" ]; then
    echo -e "$PASS SSH config exists"
else
    echo -e "$INFO No SSH config found"
fi

echo ""

# === 8. Port Exposure ===
echo "8. Port Exposure Check"
echo "----------------------"

# Check what's listening on MLX ports
echo "Checking if MLX services are exposed..."
EXPOSED=0

for port in 8080 8081 8082 8083 8084 8085; do
    if command -v lsof >/dev/null 2>&1; then
        # Check for listeners NOT on localhost (exclude 127.0.0.1 and ::1)
        LISTENER=$(lsof -i ":$port" -sTCP:LISTEN -P -n 2>/dev/null | grep -v "127.0.0.1" | grep -v "\[::1\]" | grep -v "COMMAND" || true)
        if [ -n "$LISTENER" ]; then
            echo -e "$FAIL Port $port is exposed beyond localhost!"
            echo "$LISTENER"
            ((EXPOSED++))
        fi
    fi
done

if [ $EXPOSED -eq 0 ]; then
    echo -e "$PASS No MLX services exposed beyond localhost"
else
    echo -e "$FAIL $EXPOSED ports exposed - check host binding in settings.toml"
    ((ISSUES++))
fi

echo ""

# === Summary ===
echo "========================================="
echo "Summary"
echo "========================================="

if [ $ISSUES -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed - system is secure${NC}"
elif [ $ISSUES -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) - review recommendations above${NC}"
else
    echo -e "${RED}✗ $ISSUES critical issue(s) found - fix immediately${NC}"
    [ $WARNINGS -gt 0 ] && echo -e "${YELLOW}⚠ $WARNINGS warning(s) - review recommendations above${NC}"
fi

echo ""
echo "Quick Fix Commands:"
echo "-------------------"
echo "chmod 600 config/settings.toml"
echo "chmod 600 ~/Library/Logs/com.mlx-box.*.log"
echo ""
echo "For secure deployment, ensure:"
echo "  • host = \"127.0.0.1\" in settings.toml"
echo "  • API keys are set (api_key or api_keys)"
echo "  • settings.toml is not tracked by git"
echo "  • Access via SSH tunnel or reverse proxy only"
echo ""

exit $ISSUES
