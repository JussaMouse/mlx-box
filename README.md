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

Before running the script, there are two required manual steps: setting up SSH and creating your private configuration file.

1.  **Set Up DNS:**
    Point your desired domain name (e.g., `vice.yourdomain.com`) to the public IP address of your server. This is required for SSL certificate generation.

2.  **Set Up SSH Access:**
    Place your client's public SSH key into the `authorized_keys` file on the server.
    ```sh
    mkdir -p /Users/env/.ssh && echo "ssh-ed25519 AAA..." > /Users/env/.ssh/authorized_keys
    chmod 700 /Users/env/.ssh && chmod 600 /Users/env/.ssh/authorized_keys
    ```

3.  **Create and Edit Your Configuration File:**
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
The script will install all tools, generate all configuration files (`pf.conf`, `nginx.conf`), install all services, and attempt to obtain an SSL certificate.

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

## 4. Backup and Disaster Recovery

The backup strategy separates private user data from public, replaceable code.

### 4.1. What to Back Up
-   The entire `config/` directory.
-   The stateful data directory from the `wooster` agent (e.g., `wooster/data/`).
-   The SSL certificates managed by certbot: `/etc/letsencrypt/`

**Example Backup Command:**
```sh
# Create a timestamped backup archive
sudo tar -czvf vice-backup-$(date +%Y-%m-%d).tar.gz /Users/env/server/config /Users/env/wooster/data /etc/letsencrypt
```

### 4.2. Restore Procedure
1.  Provision a fresh server using the `vice-install.sh` script (after setting up DNS, SSH, and your `config.toml` file).
2.  Transfer your latest backup file to the server.
3.  Unpack the backup archive from the root directory:
    ```sh
    # This will restore your config, wooster data, and SSL certs
    sudo tar -xzvf vice-backup-2024-01-01.tar.gz -C /
    ```
4.  Restart the services (`sudo brew services restart nginx`, etc.) to use the restored configurations.

*(Other sections like `wooster` installation, service management, and troubleshooting would be updated to reflect the new Nginx-based URLs and localhost-only service access.)*
