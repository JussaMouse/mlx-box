#!/bin/bash
#
# Vice AI Server Master Provisioning Script
#
# This script automates the complete setup of the Vice server on a fresh macOS install.
# It is designed to be idempotent and can be re-run without issue.
# See `install.md` for prerequisites and usage instructions.
#

# --- Configuration ---
# Hardcoded values for a consistent server setup.
readonly TARGET_USER="env"
readonly PYTHON_VERSION="3.11.10"
readonly NODE_VERSION="24.2"
readonly PROJECT_DIR="/Users/${TARGET_USER}/server"
readonly HOMEBREW_PACKAGES=(
    "pyenv"
    "pipx"
    "nvm"
    "htop"
    "helix"
    "tmux"
    "bandwhich"
    "jq"
)

# --- Script Setup ---
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Helper Functions ---

# A function for logging styled output.
log() {
    echo "🔵 [VICE-INSTALL] $1"
}

# A function for logging success messages.
success() {
    echo "✅ [VICE-INSTALL] $1"
}

# --- Main Script ---

log "Starting Vice AI Server provisioning..."

# --- Initial Checks ---

# 1. Check if running as the correct user.
if [[ "$(whoami)" != "${TARGET_USER}" ]]; then
    log "❌ ERROR: This script must be run by the '${TARGET_USER}' user. Current user: $(whoami)."
    exit 1
fi

# 2. Check for sudo privileges upfront.
log "This script requires sudo privileges to install system services."
sudo -v # Ask for password now to avoid prompts later.
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


# --- Phase 1: System Prerequisites ---

log "Phase 1: Installing System Prerequisites with Homebrew..."

# 1. Install Homebrew if it's not present.
if ! command -v brew &> /dev/null; then
    log "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add Homebrew to PATH for this script's session.
    eval "$(/opt/homebrew/bin/brew shellenv)"
    success "Homebrew installed."
else
    success "Homebrew is already installed."
fi

# 2. Install all required packages.
log "Installing Homebrew packages: ${HOMEBREW_PACKAGES[*]}..."
for pkg in "${HOMEBREW_PACKAGES[@]}"; do
    if ! brew list --formula | grep -q "^${pkg}\$"; then
        brew install "${pkg}"
    else
        log "${pkg} is already installed, skipping."
    fi
done
success "All Homebrew packages are installed."


# --- Phase 2: Environment Setup ---

log "Phase 2: Configuring Shell, Python, and Node.js environments..."

ZSHRC_FILE="/Users/${TARGET_USER}/.zshrc"

# 1. Configure .zshrc with required paths if not already present.
touch "${ZSHRC_FILE}" # Ensure the file exists
if ! grep -q 'eval "$(/opt/homebrew/bin/brew shellenv)"' "${ZSHRC_FILE}"; then
    log "Adding Homebrew environment to .zshrc..."
    echo '# Homebrew Path' >> "${ZSHRC_FILE}"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${ZSHRC_FILE}"
fi
if ! grep -q 'export NVM_DIR=' "${ZSHRC_FILE}"; then
    log "Adding NVM environment to .zshrc..."
    echo '# NVM Path' >> "${ZSHRC_FILE}"
    echo 'export NVM_DIR="$HOME/.nvm"' >> "${ZSHRC_FILE}"
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "${ZSHRC_FILE}"
fi
success ".zshrc configuration is up to date."

# 2. Setup Python environment.
source "${ZSHRC_FILE}"
if ! pyenv versions --bare | grep -q "^${PYTHON_VERSION}\$"; then
    log "Installing Python ${PYTHON_VERSION} with pyenv..."
    pyenv install "${PYTHON_VERSION}"
fi
pyenv global "${PYTHON_VERSION}"
pipx ensurepath
pipx install poetry
success "Python environment is configured to version ${PYTHON_VERSION}."

# 3. Setup Node.js environment.
source "${ZSHRC_FILE}"
if ! nvm ls --no-alias | grep -q "v${NODE_VERSION}"; then
    log "Installing Node.js ${NODE_VERSION} with nvm..."
    nvm install "${NODE_VERSION}"
fi
nvm use "${NODE_VERSION}"
nvm alias default "${NODE_VERSION}"
npm install -g pnpm
success "Node.js environment is configured to version ${NODE_VERSION}."


# --- Phase 3: Project Service Installation ---

log "Phase 3: Installing project services..."

# 1. Check if the project directory exists.
if [ ! -d "${PROJECT_DIR}" ]; then
    log "❌ ERROR: Project directory not found at '${PROJECT_DIR}'. Please place the project files there."
    exit 1
fi
cd "${PROJECT_DIR}"
success "Project directory found at ${PROJECT_DIR}."

# 2. Install Python dependencies.
log "Installing Python dependencies with Poetry..."
(cd "${PROJECT_DIR}/models" && poetry install)
success "Python dependencies installed."

# 3. Install all system services.
log "Installing system services (this will require your password)..."
sudo -v # Refresh sudo timestamp

log "Installing AI model services..."
(cd "${PROJECT_DIR}/models" && sudo ./startup-services-install.sh)
success "AI model services installed."

log "Installing frontend service..."
(cd "${PROJECT_DIR}/frontend" && sudo ./install-service.sh)
success "Frontend service installed."

log "Installing and activating firewall..."
(cd "${PROJECT_DIR}/firewall" && sudo ./install-firewall.sh)
success "Firewall service installed and activated."


# --- Phase 4: Finalization ---

log "Phase 4: Finalizing setup and displaying summary..."

SERVER_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || echo "Not Found")

echo ""
success "==============================================="
success "           Vice Server Provisioning Complete"
success "==============================================="
echo ""
log "The server has been configured with all necessary software and services."
log "The AI models and web frontend will start automatically on boot."
log "The firewall is active and only allows required ports."
echo ""
log "Server IP Address: ${SERVER_IP}"
log "Web Frontend URL: http://${SERVER_IP}:8000"
log "Chat API Endpoint: http://${SERVER_IP}:8080"
echo ""
log "To connect to the server via SSH, use this command from your client machine:"
echo "ssh -p 333 -i /path/to/your/jussa.skey ${TARGET_USER}@${SERVER_IP}"
echo ""
success "Setup is complete. A reboot is recommended to ensure all services start correctly."
