# Vice Server Provisioning Guide (`install.md`)

This document provides instructions for using the `vice-install.sh` script to perform a full, automated setup of the Vice AI server on a fresh macOS machine.

---

## 1. Prerequisites

Before running the installation script, ensure the following conditions are met:

1.  **Fresh macOS Install:** The script is designed to be run on a clean macOS installation (Sonoma or later recommended).
2.  **Admin User Account:** An administrator account with the username `env` must be created. The script is hardcoded to this username for paths and service configurations.
3.  **Xcode Command Line Tools:** The script will prompt you to install these if they are missing, but it's faster to install them beforehand:
    ```sh
    xcode-select --install
    ```
4.  **Internet Connection:** The script needs to download Homebrew, packages, and AI models.
5.  **Project Files:** The entire `vice-server` project directory must be present on the target machine, typically in `/Users/env/server`.
6.  **SSH Public Key:** The **one manual step** required is to place the client's public SSH key into the `authorized_keys` file on the server. The script cannot and will not handle private keys.
    ```sh
    # On the server, before running the script:
    mkdir -p /Users/env/.ssh
    echo "ssh-ed25519 AAA... your_public_key_string" > /Users/env/.ssh/authorized_keys
    chmod 700 /Users/env/.ssh
    chmod 600 /Users/env/.ssh/authorized_keys
    ```

---

## 2. The Installation Script (`vice-install.sh`)

The `vice-install.sh` script is designed to be idempotent, meaning it can be run multiple times without causing issues. If a component is already installed or configured, the script will skip it.

### What the Script Does:

-   **Sets Hostname:** Configures the server's network name to `vice`.
-   **Installs System Tools:** Installs Homebrew and all necessary packages (`pyenv`, `nvm`, `tmux`, `jq`, etc.).
-   **Configures Environments:** Sets up the correct Python and Node.js versions.
-   **Configures Shell:** Appends necessary configurations to the user's `.zshrc` file.
-   **Installs Services:** Runs the individual installation scripts for the AI models, the web frontend, and the `pf` firewall, setting them up as persistent background services.
-   **Provides a Summary:** Finishes by displaying the server's IP address and the final SSH connection command.

---

## 3. How to Run

1.  Log in to the server `vice` at the physical console as the `env` user.
2.  Open the Terminal application.
3.  Navigate to the project's root directory:
    ```sh
    cd /path/to/your/vice-server
    ```
4.  Make the script executable:
    ```sh
    chmod +x vice-install.sh
    ```
5.  Run the script:
    ```sh
    ./vice-install.sh
    ```

You will be prompted for your password once at the beginning, as the script needs `sudo` privileges to install system services and configure the firewall. Follow any on-screen prompts. The entire process may take a significant amount of time, depending on download speeds for Homebrew packages and AI models.
