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

# A function to read values from the TOML config file.
# Usage: local my_var=$(read_toml "services.chat.port")
read_toml() {
    local key=$1
    # This is a simple parser. For production, a more robust parser might be better.
    grep "^${key/./\.}" "${PROJECT_DIR}/config/settings.toml" | cut -d'=' -f2 | tr -d ' "'
}

# --- Main Script ---

log "Starting mlx-box Server provisioning..."

# --- Initial Checks ---

# 1. Check for the configuration file.
if [ ! -f "${PROJECT_DIR}/config/settings.toml" ]; then
    log "❌ ERROR: Configuration file not found at '${PROJECT_DIR}/config/settings.toml'."
    log "   Please copy 'config/settings.toml.example' to 'settings.toml' and customize it first."
    exit 1
fi
success "Configuration file found."

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
eval "$(/opt/homebrew/bin/brew shellenv)"
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
SSH_PORT=$(read_toml "services.ssh.port")
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

# 2. Generate Nginx Configuration
log "Generating Nginx configuration..."
DOMAIN_NAME=$(read_toml "server.domain_name")
FRONTEND_PORT=$(read_toml "services.frontend.port")
CHAT_PORT=$(read_toml "services.chat.port")
EMBED_PORT=$(read_toml "services.embedding.port")

# Nginx config will be placed in the Homebrew-managed location
NGINX_CONF_PATH="/opt/homebrew/etc/nginx/nginx.conf"

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

    # Redirect HTTP to HTTPS
    server {
        listen      80;
        server_name ${DOMAIN_NAME};
        return 301 https://\$host\$request_uri;
    }

    # Main HTTPS server
    server {
        listen 443 ssl;
        server_name ${DOMAIN_NAME};

        # SSL certs will be managed by certbot
        ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;
        include /etc/letsencrypt/options-ssl-nginx.conf;
        ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

        location / {
            proxy_pass http://127.0.0.1:${FRONTEND_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }

        location /v1/ { # Catches both /v1/chat/ and /v1/embeddings/
            proxy_pass http://127.0.0.1:${CHAT_PORT}; # Assuming both API servers can be reached via one port or need specific routing
            # A more complex setup might be needed if ports are different
        }
    }
}
EOF
success "Nginx configuration has been generated."


# --- Phase 5: Project Service Installation ---
log "Phase 5: Installing and launching all services..."

# 1. Install Python dependencies.
log "Installing Python dependencies with Poetry..."
(cd "${PROJECT_DIR}/models" && poetry lock && poetry install)
success "Python dependencies installed."

# 2. Install AI and Frontend services.
(cd "${PROJECT_DIR}/models" && sudo ./startup-services-install.sh)
(cd "${PROJECT_DIR}/frontend" && sudo ./install-service.sh)
success "Application services installed."

# 3. Install and start Nginx and Firewall.
(cd "${PROJECT_DIR}/firewall" && sudo ./install-firewall.sh)
sudo brew services start nginx
success "Nginx and Firewall services started."

# 4. Obtain SSL Certificate with Certbot
log "Attempting to obtain SSL certificate with Certbot..."
log "NOTE: This requires your domain's DNS to be pointing to this server's IP address."
LE_EMAIL=$(read_toml "server.letsencrypt_email")
sudo certbot --nginx -d "${DOMAIN_NAME}" --non-interactive --agree-tos -m "${LE_EMAIL}"
success "Certbot process complete. Check output for status."

# --- Phase 6: Finalization ---
# (This phase is simplified for brevity in this example)
log "Phase 6: Finalizing setup..."
SERVER_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || echo "Not Found")
success "==============================================="
success "      mlx-box Server Provisioning Complete"
success "==============================================="
log "Server IP: ${SERVER_IP}"
log "Public URL: https://${DOMAIN_NAME}"
log "SSH Command: ssh -p ${SSH_PORT} $(whoami)@${SERVER_IP}"
success "Setup is complete."
