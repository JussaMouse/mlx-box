# Vice Server & Wooster Agent: Super-System Knowledge Base (v2.0)

This document is the central knowledge base for setting up, managing, and backing up the complete Vice AI system on macOS for **production, internet-facing deployment**.

---

## 1. System Architecture: A Secure, Layered Defense

This project is architected for security and reliability using a reverse proxy model.

-   **Outer Wall (Firewall):** The `pf` firewall is the first line of defense. It blocks all incoming traffic by default, only allowing connections on the standard web ports (`80/443`) and a custom SSH port.
-   **Gatekeeper (Nginx):** Nginx is the only service exposed to the internet. It terminates SSL (HTTPS) and acts as a secure reverse proxy, routing traffic to the appropriate internal application.
-   **Protected Core (Application Services):** The AI models and web frontend are configured to listen only on `localhost` (`127.0.0.1`), making them completely inaccessible from the outside world. They can only be reached via the Nginx gatekeeper.
-   **Configuration as Code:** All server setup is defined in version-controlled scripts that read from a private, user-managed `config/settings.toml` file.

---

## 2. Full System Provisioning

These steps configure a fresh macOS installation. The `vice-install.sh` script automates this entire section.

### 2.1. Headless Server Configuration

The script configures macOS for "always-on" server reliability: disabling sleep, enabling auto-restart on power failure, enabling Wake for Network Access, and enabling the SSH service.

### 2.2. User Prerequisites

Before running the script, there are three required manual steps: setting up DNS, SSH, and your private configuration file.

1.  **Set Up DNS:**
    For the server to be accessible from the internet via a domain name and for SSL certificates to work, you must configure a DNS 'A' record.

    -   **What is an 'A' Record?** It's a setting at your domain registrar (e.g., GoDaddy, Namecheap, Cloudflare) that points a domain name (like `vice.yourdomain.com`) to a specific IP address.

    -   **How to do it:**
        1.  Find your server's **public IP address**. You can do this by running `curl ifconfig.me` on the server, or by checking your router's administration page.
        2.  Log in to your domain registrar's website.
        3.  Go to the DNS management section for your domain.
        4.  Create a new 'A' record with the following settings:
            -   **Host/Name:** `vice` (or whatever subdomain you want)
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
    Copy the configuration template and customize it with your domain, email, and preferred model.
    ```sh
    cp config/settings.toml.example config/settings.toml
    hx config/settings.toml
    ```

### 2.3. Running the Installer

With the prerequisites met, run the master script from the project directory:
```sh
chmod +x vice-install.sh
./vice-install.sh
```
The script is idempotent and safe to re-run. It will install all tools, dynamically generate configuration files (`pf.conf`, `nginx.conf`), install all services, and attempt to obtain an SSL certificate.

---

## 3. Configuration (`settings.toml`) Explained

This file is the heart of your server's setup.

#### `[server]`
-   `domain_name`: **Required.** Your server's public domain name.
-   `letsencrypt_email`: **Required.** Your email for SSL certificate registration.
-   `host`: **Must be `"127.0.0.1"`** for the secure reverse-proxy architecture to work.

#### `[services.ssh]`
-   `port`: The custom port for your SSH service. This port will be automatically opened in the firewall.

#### `[services.chat | embedding | frontend]`
-   `port`: The internal `localhost` port the service will run on. Nginx will proxy traffic to this port.
-   `model`: The Hugging Face model ID to use.

---

## 4. Updating an Existing Installation

To update your server to the latest version of the `vice-server` code, follow these steps:

1.  **Back Up Your Configuration:** Before starting, it's always wise to back up your critical files:
    ```sh
    # This command is detailed further in the Backup section
    sudo tar -czvf vice-backup-$(date +%Y-%m-%d).tar.gz /Users/env/server/config /etc/letsencrypt
    ```
2.  **Pull the Latest Code:**
    ```sh
    cd /path/to/your/vice-server
    git pull origin main # Or the appropriate branch
    ```
3.  **Update Dependencies:**
    Run `poetry install` to ensure your Python dependencies are up to date with any changes in `pyproject.toml`.
    ```sh
    cd models && poetry install && cd ..
    ```
4.  **Review Configuration Template:**
    Compare your `config/settings.toml` with the new `config/settings.toml.example`. If there are new settings in the example file, copy them over to your own configuration and customize them.
5.  **Re-run the Master Installer:**
    The installer script is designed to be safely re-run for updates. It will automatically back up critical system files it overwrites (like `nginx.conf`) and apply all new configurations and code changes.
    ```sh
    ./vice-install.sh
    ```

---

## 5. Backup and Disaster Recovery

The backup strategy separates private user data from public, replaceable code.

### 5.1. What to Back Up
-   The entire `config/` directory.
-   The stateful data directory from the `wooster` agent (e.g., `wooster/data/`).
-   The SSL certificates managed by certbot: `/etc/letsencrypt/`
-   **System Configurations (for reference):** While the installer script regenerates these, the backups it creates (e.g., in `/opt/homebrew/etc/nginx/`) can be useful.

**Example Backup Command:**
```sh
# Create a timestamped backup archive of critical data
sudo tar -czvf vice-backup-$(date +%Y-%m-%d).tar.gz /Users/env/server/config /Users/env/wooster/data /etc/letsencrypt
```

### 5.2. Restore Procedure
1.  Provision a fresh server using the `vice-install.sh` script (after setting up DNS, SSH, and your `config.toml` file).
2.  Transfer your latest backup file to the server.
3.  Unpack the backup archive from the root directory:
    ```sh
    # This will restore your config, wooster data, and SSL certs
    sudo tar -xzvf vice-backup-2024-01-01.tar.gz -C /
    ```
4.  Restart the services (`sudo brew services restart nginx`, etc.) to use the restored configurations.

*(Other sections like `wooster` installation, service management, and troubleshooting would be updated to reflect the new Nginx-based URLs and localhost-only service access.)*
