#!/bin/bash
set -euo pipefail

# Restart the chat LaunchDaemon cleanly and verify it's running
# - Unloads the daemon to prevent respawn
# - Kills lingering chat processes
# - Boots and kickstarts the daemon
# - Verifies status and port health

LABEL="com.local.mlx-chat-server"
PLIST="/Library/LaunchDaemons/com.local.mlx-chat-server.plist"
CHAT_PORT="8080"

red() { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }

require_root() {
    if [ "${EUID}" -ne 0 ]; then
        yellow "This script needs sudo. Re-running with sudo..."
        exec sudo "$0" "$@"
    fi
}

kill_if_exists() {
    local pattern="$1"
    if pgrep -fal "$pattern" >/dev/null 2>&1; then
        yellow "Killing processes matching: $pattern"
        pkill -f "$pattern" || true
    fi
}

wait_clear() {
    local what="$1"; shift
    local check_cmd=("$@")
    local tries=0
    while [ $tries -lt 20 ]; do
        if ! "${check_cmd[@]}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
        tries=$((tries+1))
    done
    return 1
}

ensure_port_free() {
    local port="$1"
    if lsof -ti:"${port}" >/dev/null 2>&1; then
        yellow "Port ${port} busy; terminating holders"
        lsof -ti:"${port}" | xargs -r kill || true
        sleep 1
        if lsof -ti:"${port}" >/dev/null 2>&1; then
            yellow "Forcing kill on port ${port} holders"
            lsof -ti:"${port}" | xargs -r kill -9 || true
        fi
    fi
}

main() {
    require_root "$@"

    if [ ! -f "${PLIST}" ]; then
        red "Missing plist: ${PLIST}"
        red "Install services first, then retry."
        exit 1
    fi

    yellow "Unloading daemon (bootout) to prevent respawn..."
    launchctl bootout system "${PLIST}" >/dev/null 2>&1 || true

    yellow "Stopping lingering chat processes..."
    kill_if_exists 'python3 chat-server.py'
    kill_if_exists 'mlx_lm.*server.*--port 8080'

    yellow "Waiting for processes to exit..."
    if ! wait_clear "chat processes" pgrep -f 'chat-server.py\|mlx_lm.*server.*--port 8080'; then
        yellow "Forcing remaining chat processes to exit"
        pkill -9 -f 'chat-server.py\|mlx_lm.*server.*--port 8080' || true
    fi

    ensure_port_free "${CHAT_PORT}"

    yellow "Bootstrapping daemon..."
    launchctl bootstrap system "${PLIST}"

    yellow "Kickstarting daemon..."
    launchctl kickstart -k "system/${LABEL}"

    sleep 1

    if launchctl list | grep -q "${LABEL}"; then
        green "LaunchDaemon listed: ${LABEL}"
    else
        red "LaunchDaemon not listed. Check: sudo launchctl print system/${LABEL}"
        exit 1
    fi

    # Quick health check of the API endpoint
    if command -v curl >/dev/null 2>&1; then
        yellow "Checking http://127.0.0.1:${CHAT_PORT}/v1/models (5s timeout)..."
        if curl -fsS --max-time 5 "http://127.0.0.1:${CHAT_PORT}/v1/models" >/dev/null 2>&1; then
            green "Chat server responded on port ${CHAT_PORT}."
        else
            yellow "No response yet. The model may still be loading."
            yellow "Inspect logs for details."
        fi
    fi

    echo
    yellow "Useful commands:"
    echo "  sudo launchctl print system/${LABEL} | sed -n '1,120p'"
    echo "  tail -n 100 -f \"$HOME/Library/Logs/com.local.mlx-chat-server/stderr.log\""
}

main "$@"


