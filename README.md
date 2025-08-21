# mlx-box: Super-System Knowledge Base

This document is the central knowledge base for setting up, managing, and backing up the complete mlx-box AI system on macOS for **production, internet-facing deployment**.

---

## 1. System Architecture: A Secure, Layered Defense

This project is architected for security and reliability using a reverse proxy model.

-   **Outer Wall (Firewall):** The `pf` firewall is the first line of defense. It blocks all incoming traffic by default, only allowing connections on the standard web ports (`80/443`) and a custom SSH port.
-   **Gatekeeper (Nginx):** Nginx is the only service exposed to the internet. It terminates SSL (HTTPS) and acts as a secure reverse proxy, routing traffic to the appropriate internal application.
-   **Protected Core (Application Services):** The AI models and web frontend are configured to listen only on `localhost` (`127.0.0.1`), making them completely inaccessible from the outside world. They can only be reached via the Nginx gatekeeper.
-   **Configuration as Code:** All server setup is defined in version-controlled scripts that read from a private, user-managed `config/settings.toml` file.

---

## 2. Full System Provisioning

These steps configure a fresh macOS installation. The `install.sh` script automates this entire section.

### 2.1. Headless Server Configuration

The script configures macOS for "always-on" server reliability: disabling sleep, enabling auto-restart on power failure, enabling Wake for Network Access, and enabling the SSH service.

### 2.2. User Prerequisites

Before running the script, there are three required manual steps: setting up DNS, SSH, and your private configuration file.

1.  **Set Up DNS:**
    For the server to be accessible from the internet via a domain name and for SSL certificates to work, you must configure a DNS 'A' record.

    -   **What is an 'A' Record?** It's a setting at your domain registrar (e.g., GoDaddy, Namecheap, Cloudflare) that points a domain name (like `mlx-box.yourdomain.com`) to a specific IP address.

    -   **How to do it:**
        1.  Find your server's **public IP address**. You can do this by running `curl ifconfig.me` on the server, or by checking your router's administration page.
        2.  Log in to your domain registrar's website.
        3.  Go to the DNS management section for your domain.
        4.  Create a new 'A' record with the following settings:
            -   **Host/Name:** `mlx-box` (or whatever subdomain you want)
            -   **Value/Points to:** Your server's public IP address.
            -   **TTL (Time to Live):** Set to a low value initially (like 300 seconds) if you are testing.

    -   **Important:** DNS changes can take anywhere from a few minutes to a few hours to propagate across the internet. You can use a tool like [dnschecker.org](https://dnschecker.org/) to see when your new record is live before running the installer.

2.  **Configure Port Forwarding on Your Router:**
    To allow external traffic from the internet to reach your server, you must set up port forwarding on your router.

    -   **How to do it:**
        1.  Find your server's **local IP address** (e.g., `192.168.1.xxx`) by running `ipconfig getifaddr en0` on the server.
        2.  Log in to your router's administration web page.
        3.  Find the "Port Forwarding" section (it may be called "Virtual Servers" or similar).
        4.  Create the following three rules to forward traffic to your server's local IP:
            -   **SSH:** External Port `333` -> Internal Port `333` (TCP)
            -   **HTTP:** External Port `80` -> Internal Port `80` (TCP)
            -   **HTTPS:** External Port `443` -> Internal Port `443` (TCP)
        5.  Save and apply the changes. Your router may need to reboot.

3.  **Set Up SSH Access:**
    Place your client's public SSH key into the `authorized_keys` file on the server.
    ```sh
    mkdir -p /Users/env/.ssh && echo "ssh-ed25519 AAA..." > /Users/env/.ssh/authorized_keys
    chmod 700 /Users/env/.ssh && chmod 600 /Users/env/.ssh/authorized_keys
    ```

4.  **Create and Edit Your Configuration File:**
    Copy the configuration templates and customize them with your domain, email, and other settings. The `.toml` file is used by the Python services, and the `.env` file is used by the installation scripts.
    ```sh
    cp config/settings.toml.example config/settings.toml
    cp config/settings.env.example config/settings.env
    hx config/settings.toml
    hx config/settings.env
    ```

### 2.3. Running the Installer

With the prerequisites met, run the master script from the project directory:
```sh
chmod +x install.sh
./install.sh
```
The script is idempotent and safe to re-run. It will install all tools, dynamically generate configuration files (`pf.conf`, `nginx.conf`), install all services, and attempt to obtain an SSL certificate.

---

## 3. Configuration Explained

The server is configured using two files in the `config/` directory.

### `settings.env` (for the installer)

This file uses a simple `KEY=VALUE` format and is used by the shell scripts (`install.sh`, `update-model.sh`, etc.) to configure the server environment. You must copy the example file and edit it before running the installer.

-   `DOMAIN_NAME`: **Required.** Your server's public domain name.
-   `LETSENCRYPT_EMAIL`: **Required.** Your email for SSL certificate registration.
-   `SSH_PORT`: The custom port for your SSH service.
-   `CHAT_PORT`, `EMBED_PORT`, `FRONTEND_PORT`: The internal `localhost` ports for the application services.

### `settings.toml` (for the AI services)

This file is used exclusively by the Python-based AI services (`chat-server.py`, `embed-server.py`) to select which models to load.

-   `model`: The Hugging Face model ID for the chat and embedding services. You can change this to use any compatible model from the `mlx-community` library.

---

## 4. Model Management

You can easily switch to a new chat model without re-running the entire installation.

### Using the `update-model.sh` Script

The simplest method is to use the provided `update-model.sh` script. It will automatically update your configuration, restart the service, and show you the download progress.

```sh
# Make the script executable (only need to do this once)
chmod +x update-model.sh

# Run the script with the new model ID
./update-model.sh mlx-community/Llama-3-8B-Instruct-4bit
```

The script will handle the rest. The server will download the new model (which can take some time) and load it.

---

## 5. Updating Your Server

To update your server to the latest version of the `mlx-box` code, follow this procedure. This process is designed to be safe and to preserve your existing configuration and data.

### Step 1: Back Up Your System
Before any update, perform a full backup of your critical data. This gives you a safe restore point.
```sh
# Navigate to your home directory for the backup file
cd ~
# Create a timestamped backup of your config and SSL certs
sudo tar -czvf mlx-box-backup-$(date +%Y-%m-%d).tar.gz /Users/env/server/config /etc/letsencrypt
```

### Step 2: Fetch the Latest Code
Navigate to the project directory and pull the latest changes from the Git repository.
    ```sh
    cd /Users/env/server
    git pull origin main # Or your primary branch
    ```

### Step 3: Review Configuration Changes
New versions of the server may introduce new settings. It's crucial to compare your private configuration with the new template.
```sh
# Use the 'diff' command to see what's new in the example file
diff config/settings.toml config/settings.toml.example
```
After reviewing the differences, manually copy any new settings from the `.example` file into your main `config/settings.toml` and configure them.

### Step 4: Update Dependencies
The new code may require new or updated Python libraries. Run `poetry install` to sync your environment.
```sh
(cd models && poetry install)
```

### Step 5: Re-run the Master Installer
The `install.sh` script is designed to be safely re-run for updates. It will intelligently apply the latest configurations, restart services, and ensure the system is in the correct state.
    ```sh
    ./install.sh
    ```

### Step 6: Verify the Update
After the script completes, check that the services are running and accessible.
```sh
# Check the status of the Nginx service
sudo launchctl list | grep nginx

# Check the application logs for any errors
tail -f ~/Library/Logs/com.mlx-box.frontend-server/stderr.log
```

---

## 6. Backup and Disaster Recovery

The backup strategy separates private user data from public, replaceable code.

### 5.1. What to Back Up
-   The entire `config/` directory.
-   The SSL certificates managed by certbot: `/etc/letsencrypt/`
-   **System Configurations (for reference):** While the installer script regenerates these, the backups it creates (e.g., in `/opt/homebrew/etc/nginx/`) can be useful.

**Example Backup Command:**
```sh
# Create a timestamped backup archive of critical data
sudo tar -czvf mlx-box-backup-$(date +%Y-%m-%d).tar.gz /Users/env/server/config /etc/letsencrypt
```

### 5.2. Restore Procedure
1.  Provision a fresh server using the `install.sh` script (after setting up DNS, SSH, and your `config/` files).
2.  Transfer your latest backup file to the server.
3.  Unpack the backup archive from the root directory:
    ```sh
    # This will restore your config and SSL certs
    sudo tar -xzvf mlx-box-backup-2024-01-01.tar.gz -C /
    ```
4.  Restart the services (`sudo launchctl kickstart -k system/homebrew.mxcl.nginx`, etc.) to use the restored configurations.

*(Other sections like `wooster` installation, service management, and troubleshooting would be updated to reflect the new Nginx-based URLs and localhost-only service access.)*
