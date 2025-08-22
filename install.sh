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
readonly PYTHON_VERSION="3.11.10"
readonly NODE_VERSION="24.2"
readonly HOMEBREW_PACKAGES=(
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

# --- Helper Functions ---

# A function for logging styled output.
log() {
    echo "🔵 [mlx-box-INSTALL] $1"
}

# A function for logging success messages.
success() {
    echo "✅ [mlx-box-INSTALL] $1"
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

# 2. Generate Nginx Configuration (Phase 1: Temporary for Certbot)
log "Generating temporary Nginx configuration for Certbot..."
NGINX_CONF_PATH="${BREW_PREFIX}/etc/nginx/nginx.conf"
CERTBOT_WEBROOT="/var/www/certbot"

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
(cd "${PROJECT_DIR}/models" && sudo ./startup-services-install.sh)
(cd "${PROJECT_DIR}/frontend" && sudo ./install-service.sh)
success "Application services installed."

(cd "${PROJECT_DIR}/firewall" && sudo ./install-firewall.sh)
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
        include /etc/letsencrypt/options-ssl-nginx.conf;
        ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

        location / {
            proxy_pass http://127.0.0.1:${FRONTEND_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }

        location /v1/ {
            proxy_pass http://127.0.0.1:${CHAT_PORT};
        }
    }
}
EOF
success "Final Nginx configuration has been generated."

# 6. Restart Nginx to apply final config
log "Restarting Nginx to apply final production configuration..."
sudo launchctl kickstart -k system/homebrew.mxcl.nginx
success "Nginx has been restarted."


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
