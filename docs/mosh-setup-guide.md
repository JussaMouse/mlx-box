# Mosh + tmux setup guide (macOS + iTerm2)

Use Mosh for resilient SSH (survives Wi‑Fi changes, roaming, sleep) and tmux on the server to preserve shells and long‑running tasks.

---

## 1) Install locally (Mac)

```bash
# Homebrew (recommended)
brew install mosh
```

## 2) Install on your server(s)

Ubuntu/Debian:
```bash
sudo apt update && sudo apt install -y mosh tmux
```
RHEL/CentOS/Fedora:
```bash
sudo dnf install -y mosh tmux
```
Arch:
```bash
sudo pacman -S mosh tmux
```

macOS (as a server):
```bash
# 1) Enable SSH (Remote Login)
# UI: System Settings → General → Sharing → Remote Login: On
# or CLI:
sudo systemsetup -setremotelogin on 2>/dev/null || sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist

# 2) Install Homebrew if needed (https://brew.sh), then:
brew install mosh tmux
```

If the macOS Application Firewall is enabled, allow `mosh-server`:
```bash
# Choose the correct Homebrew path
if [ -x /opt/homebrew/bin/mosh-server ]; then APP=/opt/homebrew/bin/mosh-server; else APP=/usr/local/bin/mosh-server; fi
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$APP"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$APP"
```
Note: macOS’s firewall is app-based, so you don’t open UDP ports directly. If there is a network firewall upstream, allow UDP 60000–61000 (or your chosen Mosh range).

## 3) Open UDP ports on the server

Mosh uses UDP (default dynamic range 60000–61000). Open them (or a smaller range you choose).

UFW:
```bash
sudo ufw allow 60000:61000/udp
```
firewalld:
```bash
sudo firewall-cmd --add-port=60000-61000/udp --permanent
sudo firewall-cmd --reload
```
Cloud firewalls (AWS/GCP/Azure): add an inbound UDP rule for that range.

To use a smaller range, pass it when connecting and open the same range in your firewall, e.g. 60010–60020:
```bash
mosh --port=60010:60020 user@server
```

## 4) Connect via Mosh and always land in tmux

Use tmux "attach or create" so your workspace persists on the server even if your Mac sleeps.

Ad‑hoc:
```bash
mosh user@server -- tmux new -As main
```

Convenient local alias (add to ~/.zshrc on macOS):
```bash
alias mserver='mosh --ssh="ssh -p 22" user@server -- tmux new -As main'
```
Reload your shell:
```bash
source ~/.zshrc
```

Optional: identity file, ProxyJump, or constrained port range:
```bash
# Custom identity and port
mosh --ssh="ssh -i ~/.ssh/id_ed25519 -p 22" user@server -- tmux new -As main

# Via a bastion/jump host
mosh --ssh="ssh -J jumpuser@jump.example.com" user@target -- tmux new -As main

# Constrain Mosh UDP ports
mosh --port=60010:60020 user@server -- tmux new -As main
```

## 5) iTerm2 profile (click‑to‑connect)

- iTerm2 → Settings → Profiles → +
- General → Command: "Command"
- Command:
```bash
mosh --ssh="ssh -p 22" user@server -- tmux new -As main
```
- Name it (e.g., "server‑mosh") and save. Open this profile to connect.

## 6) Optional: auto‑start tmux on SSH login

Add to the server’s shell RC so SSH sessions start or attach to tmux automatically (interactive shells only):

Bash (~/.bashrc):
```bash
case $- in *i*) :;; *) return;; esac
[ -z "$TMUX" ] && [ -n "$SSH_CONNECTION" ] && exec tmux new -As main
```

Zsh (~/.zshrc):
```bash
if [[ $- == *i* ]] && [[ -n $SSH_CONNECTION ]] && [[ -z $TMUX ]]; then
  exec tmux new -As main
fi
```

You can then shorten your command to just `mosh user@server`.

## 7) Verify behavior

- Connect with your alias/profile; you should see a tmux status bar.
- Toggle Wi‑Fi, move networks, or close the lid; after wake, the session should resume instantly.
- Your tmux session persists as long as the server stays up. If the server reboots, reconnect and run `tmux attach -t main` (unless you supervise tmux with a service).

## 8) Troubleshooting

- Mosh won’t connect (hangs): likely UDP blocked. Fallback to plain SSH + tmux:
```bash
ssh user@server -t 'tmux new -As main'
```
- Ensure server firewall/cloud rules allow your chosen UDP range.
- Check versions:
```bash
mosh --version
mosh-server -h
tmux -V
```

## 9) Notes & limitations

- Mosh provides roaming and intermittent connectivity tolerance but does not support SSH port/X11 forwarding. Use plain SSH when you need those.
- macOS outbound UDP is fine; only the server needs inbound UDP open.
- For multiple servers, create one alias/profile per host.

---

Happy roaming! Your shells and processes keep running in tmux, while Mosh keeps the connection usable through sleep and network changes.
