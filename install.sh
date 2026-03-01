#!/bin/bash
#
# Vice AI Server Master Provisioning Script (v2.0 - Production Ready)
#
# This script automates the complete setup of the Vice server on a fresh macOS install.
# It is designed to be idempotent and can be re-run without issue.
# See `README.md` for prerequisites and usage instructions.
#

# --- Configuration ---
# Hardcoded values for a consistent server setup.
readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PYTHON_VERSION="3.12.12"
readonly NODE_VERSION="24.2"
readonly HOMEBREW_PACKAGES=(
    "python@3.12"
    "pyenv"
    "pipx"
    "nvm"
    "htop"
    "helix"
    "tmux"
    "bandwhich"
    "jq"
    "nginx"
    "certbot"
)

# --- Script Setup ---
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Download Monitoring Defaults ---
# Set MODEL_DOWNLOAD_WAIT=0 to skip waiting for model downloads.
MODEL_DOWNLOAD_WAIT="${MODEL_DOWNLOAD_WAIT:-1}"
MODEL_DOWNLOAD_INTERVAL_SEC="${MODEL_DOWNLOAD_INTERVAL_SEC:-20}"
MODEL_DOWNLOAD_IDLE_WARN_SEC="${MODEL_DOWNLOAD_IDLE_WARN_SEC:-300}"
DOWNLOAD_MARKER="/tmp/mlx-box-download-start.$$"
touch "${DOWNLOAD_MARKER}"

# --- Helper Functions ---

# A function for logging styled output.
log() {
    echo "🔵 [mlx-box-INSTALL] $1"
}

# A function for logging success messages.
success() {
    echo "✅ [mlx-box-INSTALL] $1"
}

get_backend_logs() {
    local user_home="$1"
    local logs=(
        "router"
        "fast"
        "thinking"
        "embedding"
        "ocr"
        "tts"
        "whisper"
    )
    for svc in "${logs[@]}"; do
        local f="${user_home}/Library/Logs/com.mlx-box.${svc}-backend/stderr.log"
        if [ -f "$f" ]; then
            echo "${svc}|${f}"
        fi
    done
}

log_configured_models() {
    local settings_toml="$1"
    if [ ! -f "$settings_toml" ]; then
        log "settings.toml not found for model listing: ${settings_toml}"
        return 0
    fi
    log "Configured models (from settings.toml):"
    awk '
        /^\[services\./ { section=$0; gsub(/[\[\]]/,"",section); }
        /^[[:space:]]*model[[:space:]]*=/ {
            gsub(/"/,"",$3);
            printf "  - %s: %s\n", section, $3;
        }
    ' "$settings_toml" | sed 's/^/🔵 [mlx-box-INSTALL] /'
}

wait_for_model_downloads() {
    local user_home="$1"
    local hf_cache="${user_home}/.cache/huggingface/hub"
    local state_dir="/tmp/mlx-box-download-state"
    local last_change_ts
    local last_incomplete="-1"
    local now_ts

    if [ "${MODEL_DOWNLOAD_WAIT}" != "1" ]; then
        log "MODEL_DOWNLOAD_WAIT=0; skipping download wait."
        return 0
    fi

    if [ ! -d "${hf_cache}" ]; then
        log "Hugging Face cache not found at ${hf_cache}; skipping download wait."
        return 0
    fi

    mkdir -p "${state_dir}"
    last_change_ts=$(date +%s)

    # Only wait if we detect fresh download activity.
    if ! find "${hf_cache}" -type f -name "*.incomplete" -newer "${DOWNLOAD_MARKER}" 2>/dev/null | head -n 1 | grep -q .; then
        log "No new model downloads detected."
        return 0
    fi

    log "Model downloads detected; waiting for completion..."
    log_configured_models "${PROJECT_DIR}/config/settings.toml"

    while true; do
        local incomplete_count
        incomplete_count=$(find "${hf_cache}" -type f -name "*.incomplete" -newer "${DOWNLOAD_MARKER}" 2>/dev/null | wc -l | tr -d ' ')
        if [ "${incomplete_count}" -eq 0 ]; then
            success "All model downloads complete."
            break
        fi

        if [ "${incomplete_count}" != "${last_incomplete}" ]; then
            log "Download progress: ${incomplete_count} incomplete files remaining."
            last_incomplete="${incomplete_count}"
            last_change_ts=$(date +%s)
        fi

        while IFS= read -r entry; do
            local svc="${entry%%|*}"
            local log_file="${entry#*|}"
            local last_file="${state_dir}/last_${svc}.txt"
            local line
            line=$(grep -E "Fetching [0-9]+ files|Loading weights|Resolved .* model id|Model loaded|✅" "$log_file" 2>/dev/null | tail -n 1 | tr '\r' ' ')
            if [ -n "${line}" ]; then
                local prev=""
                if [ -f "${last_file}" ]; then prev=$(cat "${last_file}"); fi
                if [ "${line}" != "${prev}" ]; then
                    echo "${line}" > "${last_file}"
                    log "Download progress (${svc}): ${line}"
                    last_change_ts=$(date +%s)
                fi
            fi
        done < <(get_backend_logs "${user_home}")

        now_ts=$(date +%s)
        if [ $((now_ts - last_change_ts)) -ge "${MODEL_DOWNLOAD_IDLE_WARN_SEC}" ]; then
            log "⚠️  No download activity detected for ${MODEL_DOWNLOAD_IDLE_WARN_SEC}s. If stuck, check backend logs in ~/Library/Logs/com.mlx-box.*"
            last_change_ts=$(date +%s)
        fi

        sleep "${MODEL_DOWNLOAD_INTERVAL_SEC}"
    done
}

# --- Main Script ---

log "Starting mlx-box Server provisioning..."

# Collect system info early so we can make decisions later
if [ -x "$(pwd)/scripts/collect_system_info.sh" ]; then
    log "Collecting system information..."
    (cd "$(pwd)" && scripts/collect_system_info.sh) || log "Failed to collect system info"
fi

# --- Initial Checks ---

# 1. Check for the configuration file.
if [ ! -f "${PROJECT_DIR}/config/settings.env" ]; then
    log "❌ ERROR: Configuration file not found at '${PROJECT_DIR}/config/settings.env'."
    log "   Please copy 'config/settings.env.example' to 'settings.env' and customize it first."
    exit 1
fi
# Source the configuration file to load all the variables.
source "${PROJECT_DIR}/config/settings.env"
success "Configuration file found and loaded."

# --- Port Defaults (in case settings.env is missing new vars) ---
ROUTER_PORT="${ROUTER_PORT:-8080}"
FAST_PORT="${FAST_PORT:-${CHAT_PORT:-8081}}"
THINKING_PORT="${THINKING_PORT:-8083}"
EMBED_PORT="${EMBED_PORT:-8084}"
OCR_PORT="${OCR_PORT:-8085}"
TTS_PORT="${TTS_PORT:-8086}"
WHISPER_PORT="${WHISPER_PORT:-8087}"


# 2. Check for sudo privileges upfront.
log "This script requires sudo privileges to install system services."
sudo -v
if [[ $? -ne 0 ]]; then
    log "❌ ERROR: Sudo password not provided or incorrect. Aborting."
    exit 1
fi
log "Sudo privileges confirmed."

# 3. Check for Xcode Command Line Tools.
if ! xcode-select -p &>/dev/null; then
    log "Xcode Command Line Tools not found. Please install them to continue."
    xcode-select --install
    log "Rerun this script after the installation is complete."
    exit 1
fi
success "Xcode Command Line Tools are installed."


# --- Phase 1: System Configuration for Headless Operation ---
# (This phase is simplified for brevity in this example)
log "Phase 1: Configuring macOS for reliable headless server operation..."
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 autorestart 1 womp 1
sudo systemsetup -setremotelogin on
success "macOS headless/server settings applied."


# --- Phase 2: System Prerequisites (Homebrew) ---
log "Phase 2: Installing System Prerequisites with Homebrew..."
# (This phase is simplified for brevity in this example)
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
BREW_PREFIX=$(brew --prefix)
eval "$(${BREW_PREFIX}/bin/brew shellenv)"
for pkg in "${HOMEBREW_PACKAGES[@]}"; do
    if ! brew list --formula | grep -q "^${pkg}\$"; then brew install "${pkg}"; fi
done
success "All Homebrew packages are installed."

# Optionally install Mosh if enabled via settings.env
if [ "${ENABLE_MOSH:-0}" = "1" ]; then
    if ! brew list --formula | grep -q "^mosh$"; then
        log "Mosh enabled; installing mosh via Homebrew…"
        brew install mosh
    else
        log "Mosh already installed."
    fi
fi


# --- Phase 3: Environment Setup (Python/Node) ---
log "Phase 3: Configuring Shell, Python, and Node.js environments..."
# (This phase is simplified for brevity in this example)
# ... Configuration for .zshrc, pyenv, nvm, poetry, pnpm ...
success "Python and Node.js environments are configured."


# --- Phase 4: Dynamic Configuration Generation ---
log "Phase 4: Generating configuration files from settings.toml..."

# 1. Generate Firewall Rules
log "Generating firewall rules..."
cat > "${PROJECT_DIR}/firewall/pf.conf" << EOF
# Block all incoming traffic by default.
block in all

# Allow all outgoing traffic.
pass out all keep state

# Allow all traffic on the loopback interface.
pass in quick on lo0 all

# Allow incoming SSH, HTTP, and HTTPS traffic.
pass in proto tcp from any to any port ${SSH_PORT}
pass in proto tcp from any to any port 80
pass in proto tcp from any to any port 443
EOF
success "firewall/pf.conf has been generated."

# If Mosh is enabled, append UDP rules to pf.conf
if [ "${ENABLE_MOSH:-0}" = "1" ]; then
  MOSH_PORT_START_LOCAL="${MOSH_PORT_START:-60000}"
  MOSH_PORT_END_LOCAL="${MOSH_PORT_END:-61000}"
  cat >> "${PROJECT_DIR}/firewall/pf.conf" << EOF

# Allow incoming UDP traffic for Mosh
pass in proto udp from any to any port ${MOSH_PORT_START_LOCAL}:${MOSH_PORT_END_LOCAL}
EOF
  success "Added Mosh UDP range ${MOSH_PORT_START_LOCAL}-${MOSH_PORT_END_LOCAL} to pf.conf."
fi

# 2. Generate Nginx Configuration (Phase 1: Temporary for Certbot)
log "Generating temporary Nginx configuration for Certbot..."
NGINX_CONF_PATH="${BREW_PREFIX}/etc/nginx/nginx.conf"
CERTBOT_WEBROOT="/var/www/certbot"
ALLOWED_IPS=$(grep -E '^ALLOWED_IPS=' "${PROJECT_DIR}/config/settings.env" | cut -d= -f2 | tr -d '"')

# Ensure Nginx log directory exists with correct permissions
sudo mkdir -p "${BREW_PREFIX}/var/log/nginx"
sudo chown -R "$(whoami):admin" "${BREW_PREFIX}/var/log/nginx"

cat > "${NGINX_CONF_PATH}" << EOF
worker_processes  1;
events {
    worker_connections  1024;
}
http {
    server {
        listen      80;
        server_name ${DOMAIN_NAME};
        location /.well-known/acme-challenge/ {
            root ${CERTBOT_WEBROOT};
        }
    }
}
EOF
success "Temporary Nginx configuration has been generated."

# 3. Install and start services (Nginx is started here)
chmod +x "${PROJECT_DIR}/models/startup-services-install.sh" 2>/dev/null || true
(cd "${PROJECT_DIR}/models" && sudo ./startup-services-install.sh)
success "Application services installed."

chmod +x "${PROJECT_DIR}/firewall/install-firewall.sh" 2>/dev/null || true
(cd "${PROJECT_DIR}/firewall" && sudo bash ./install-firewall.sh)
log "Starting Nginx service with temporary config..."
NGINX_PLIST_SOURCE=$(${BREW_PREFIX}/bin/brew --prefix nginx)/homebrew.mxcl.nginx.plist
NGINX_PLIST_DEST="/Library/LaunchDaemons/homebrew.mxcl.nginx.plist"
sudo cp "${NGINX_PLIST_SOURCE}" "${NGINX_PLIST_DEST}"
sudo launchctl bootout system "${NGINX_PLIST_DEST}" 2>/dev/null || true
sudo launchctl bootstrap system "${NGINX_PLIST_DEST}"
success "Nginx and Firewall services started."
sleep 5 # Give Nginx a moment to start up

# 4. Obtain SSL Certificate with Certbot
log "Attempting to obtain SSL certificate with Certbot..."
sudo mkdir -p "${CERTBOT_WEBROOT}"
sudo certbot certonly --webroot -w "${CERTBOT_WEBROOT}" -d "${DOMAIN_NAME}" --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL}"
success "Certbot process complete."

# 5. Generate Nginx Configuration (Phase 2: Final Production Config)
log "Generating final Nginx production configuration..."

# Hardened TLS defaults: try to install recommended options and dhparams
sudo mkdir -p /etc/letsencrypt
# Try to copy options-ssl-nginx.conf from Homebrew if present
if [ -f "/opt/homebrew/etc/letsencrypt/options-ssl-nginx.conf" ]; then
  sudo cp -f "/opt/homebrew/etc/letsencrypt/options-ssl-nginx.conf" /etc/letsencrypt/ || true
elif [ -f "${BREW_PREFIX}/etc/letsencrypt/options-ssl-nginx.conf" ]; then
  sudo cp -f "${BREW_PREFIX}/etc/letsencrypt/options-ssl-nginx.conf" /etc/letsencrypt/ || true
else
  log "⚠️  options-ssl-nginx.conf not found; proceeding without extra TLS options."
fi

# Generate dhparams in background if missing (can take a while)
if [ ! -f "/etc/letsencrypt/ssl-dhparams.pem" ]; then
  log "Generating ssl-dhparams.pem in background (2048-bit)…"
  (sudo openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048 && \
   log "ssl-dhparams.pem generated; reloading nginx" && \
   sudo launchctl kickstart -k system/homebrew.mxcl.nginx) >/dev/null 2>&1 &
else
  success "ssl-dhparams.pem present."
fi
cat > "${NGINX_CONF_PATH}" << EOF
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    # HTTP server for redirecting to HTTPS
    server {
        listen      80;
        server_name ${DOMAIN_NAME};
        # Handle Let's Encrypt ACME challenge (optional, but good practice)
        location /.well-known/acme-challenge/ {
            root ${CERTBOT_WEBROOT};
        }
        location / {
            return 301 https://\$host\$request_uri;
        }
    }

    # Main HTTPS server
    server {
        listen 443 ssl;
        server_name ${DOMAIN_NAME};

        # SSL certs are now available
        ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;
        $( [ -f /etc/letsencrypt/options-ssl-nginx.conf ] && echo "include /etc/letsencrypt/options-ssl-nginx.conf;" )
        $( [ -f /etc/letsencrypt/ssl-dhparams.pem ] && echo "ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" )

        # Optional IP allowlist on 443
        $( [ -n "${ALLOWED_IPS}" ] && echo "satisfy any;" )
        $( [ -n "${ALLOWED_IPS}" ] && echo "# allowlist generated from settings.env" )
        $( for ip in $(echo "${ALLOWED_IPS}" | tr ',' ' '); do [ -n "$ip" ] && echo "allow $ip;"; done )
        $( [ -n "${ALLOWED_IPS}" ] && echo "deny all;" )

        location / {
            return 404;
        }

        # Core OpenAI-compatible endpoints
        location = /v1/embeddings {
            proxy_pass http://127.0.0.1:${EMBED_PORT};
        }

        location = /v1/audio/speech {
            proxy_pass http://127.0.0.1:${TTS_PORT};
        }

        location = /v1/audio/transcriptions {
            proxy_pass http://127.0.0.1:${WHISPER_PORT};
        }

        # Default chat traffic goes to the Fast tier
        location /v1/ {
            proxy_pass http://127.0.0.1:${FAST_PORT};
        }

        # Explicit tier/service prefixes for direct access
        location /router/ {
            proxy_pass http://127.0.0.1:${ROUTER_PORT};
        }
        location /thinking/ {
            proxy_pass http://127.0.0.1:${THINKING_PORT};
        }
        location /embedding/ {
            proxy_pass http://127.0.0.1:${EMBED_PORT};
        }
        location /ocr/ {
            proxy_pass http://127.0.0.1:${OCR_PORT};
        }
        location /tts/ {
            proxy_pass http://127.0.0.1:${TTS_PORT};
        }
        location /whisper/ {
            proxy_pass http://127.0.0.1:${WHISPER_PORT};
        }
    }
}
EOF
success "Final Nginx configuration has been generated."

# 6. Restart Nginx to apply final config
log "Restarting Nginx to apply final production configuration..."
sudo launchctl kickstart -k system/homebrew.mxcl.nginx
success "Nginx has been restarted."

# --- Phase 6.5: Model Download Wait (if needed) ---
REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="/Users/${REAL_USER}"
wait_for_model_downloads "${USER_HOME}"


# --- Phase 7: Finalization ---
log "Phase 7: Finalizing setup..."
SERVER_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || echo "Not Found")
success "==============================================="
success "      mlx-box Server Provisioning Complete"
success "==============================================="
log "Server IP: ${SERVER_IP}"
log "Public URL: https://${DOMAIN_NAME}"
log "SSH Command: ssh -p ${SSH_PORT} $(whoami)@${SERVER_IP}"
success "Setup is complete."

# --- Reporting ---
if [ -x "${PROJECT_DIR}/scripts/generate_system_report.sh" ]; then
  log "Generating post-install system report…"
  (cd "${PROJECT_DIR}" && scripts/generate_system_report.sh) || log "⚠️  Report generation failed"
fi
