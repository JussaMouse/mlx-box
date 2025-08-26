#!/bin/bash
set -euo pipefail

# Stop the chat LaunchDaemon cleanly and ensure all related processes are gone
#
# Actions:
# - bootout the LaunchDaemon to prevent respawn
# - kill lingering chat server / mlx_lm processes
# - free port 8080 if still held

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
    local desc="$1"; shift
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
        yellow "Plist not found: ${PLIST}. Continuing to kill processes anyway."
    else
        yellow "Booting out LaunchDaemon to prevent respawn..."
        launchctl bootout system "${PLIST}" >/dev/null 2>&1 || true
    fi

    yellow "Stopping lingering chat processes..."
    kill_if_exists 'python3 chat-server.py'
    kill_if_exists 'mlx_lm.*server.*--port 8080'

    yellow "Waiting for processes to exit..."
    if ! wait_clear "chat processes" pgrep -f 'chat-server.py\|mlx_lm.*server.*--port 8080'; then
        yellow "Forcing remaining chat processes to exit"
        pkill -9 -f 'chat-server.py\|mlx_lm.*server.*--port 8080' || true
    fi

    ensure_port_free "${CHAT_PORT}"

    if pgrep -fal 'mlx_lm|chat-server.py' >/dev/null 2>&1; then
        red "Some processes still remain:"
        pgrep -fal 'mlx_lm|chat-server.py' || true
        exit 1
    fi

    if lsof -ti:"${CHAT_PORT}" >/dev/null 2>&1; then
        red "Port ${CHAT_PORT} is still in use. Check processes with: lsof -i :${CHAT_PORT}"
        exit 1
    fi

    green "Chat service stopped and port ${CHAT_PORT} is free."
    yellow "To keep it disabled across sessions: sudo launchctl disable system/${LABEL}"
}

main "$@"


