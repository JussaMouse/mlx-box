# Local AI Model Services - Management Guide

## Service Status
Check if services are running:
```bash
launchctl list | grep com.local
```

## Log Monitoring
View real-time logs for the AI services. These are located in your user's Library folder.
```bash
# Get the current user's home directory
REAL_USER=${SUDO_USER:-$(whoami)}
LOG_DIR="/Users/${REAL_USER}/Library/Logs"

# Embedding server logs
tail -f "${LOG_DIR}/com.local.embed-server/stderr.log"

# OCR (vision) server logs
tail -f "${LOG_DIR}/com.local.ocr-server/stderr.log"

# Chat tier logs
tail -f "${LOG_DIR}/com.local.mlx-router/stderr.log"
tail -f "${LOG_DIR}/com.local.mlx-fast/stderr.log"
tail -f "${LOG_DIR}/com.local.mlx-thinking/stderr.log"
```

## Service Management Commands

### Stop Services (temporary)
```bash
sudo launchctl kill SIGTERM system/com.local.embed-server
sudo launchctl kill SIGTERM system/com.local.ocr-server
sudo launchctl kill SIGTERM system/com.local.mlx-router
sudo launchctl kill SIGTERM system/com.local.mlx-fast
sudo launchctl kill SIGTERM system/com.local.mlx-thinking
```

### Fully unload (prevents respawn)
```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.local.embed-server.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.local.ocr-server.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.local.mlx-router.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.local.mlx-fast.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.local.mlx-thinking.plist
```

### Clean up lingering processes
```bash
pkill -f 'mlx_lm.*server' 2>/dev/null || true
pkill -f 'chat-server.py' 2>/dev/null || true
pkill -f 'embed-server.py' 2>/dev/null || true
pkill -f 'ocr-server.py' 2>/dev/null || true
```

### Verify processes and ports
```bash
pgrep -fal 'mlx_lm|chat-server.py|embed-server.py|ocr-server.py' || echo "No matching processes."
lsof -i :8080 -i :8081 -i :8082 -i :8083 -i :8085 | cat
```

### Start Services
```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.embed-server.plist
sudo launchctl kickstart -k system/com.local.embed-server

sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.ocr-server.plist
sudo launchctl kickstart -k system/com.local.ocr-server

sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.mlx-router.plist
sudo launchctl kickstart -k system/com.local.mlx-router

sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.mlx-fast.plist
sudo launchctl kickstart -k system/com.local.mlx-fast

sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.mlx-thinking.plist
sudo launchctl kickstart -k system/com.local.mlx-thinking
```

### Restart Services
The `kickstart` command is the modern and safest way to restart a service.
```bash
# Restart the embedding server
sudo launchctl kickstart -k system/com.local.embed-server

# Restart the OCR server
sudo launchctl kickstart -k system/com.local.ocr-server

# Restart chat tiers
sudo launchctl kickstart -k system/com.local.mlx-router
sudo launchctl kickstart -k system/com.local.mlx-fast
sudo launchctl kickstart -k system/com.local.mlx-thinking
```

### Disable/Enable on boot
```bash
sudo launchctl disable system/com.local.ocr-server
sudo launchctl enable system/com.local.ocr-server
```

## Model Management
The easiest way to update the chat model is to use the `update-model.sh` script in the project's root directory. See the main `README.md` for details.
```bash
# From the project root
./update-model.sh fast mlx-community/New-Model-Name-4bit
./update-model.sh ocr mlx-community/olmOCR-2-7B-1025-mlx-8bit
```

## Test Endpoints
After installation, test these endpoints (wait 2-5 minutes for startup):

### Check if services are responding:
```bash
# Test embedding server
curl http://127.0.0.1:8083/v1/models

# Test chat tiers
curl http://127.0.0.1:8082/v1/models
curl http://127.0.0.1:8080/v1/models
curl http://127.0.0.1:8081/v1/models

# Test OCR server
curl http://127.0.0.1:8085/v1/models
```

### Test embedding functionality:
```bash
curl -X POST http://127.0.0.1:8083/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-Embedding-4B",
    "input": "Hello world"
  }'
```

### Test chat functionality:
```bash
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Qwen2.5-72B-Instruct-4bit",
    "messages": [{"role": "user", "content": "Hello! Can you confirm you are working?"}],
    "max_tokens": 50,
    "temperature": 0.7
  }'
```

### Browser-friendly test URLs:
- **Embedding API**: http://127.0.0.1:8083/v1/models
- **Chat API**: http://127.0.0.1:8080/v1/models
- **OCR API**: http://127.0.0.1:8085/v1/models

## Troubleshooting

### Check if ports are in use:
```bash
lsof -i :8080 -i :8081
```

### Check service status:
```bash
sudo launchctl list | grep com.local
```

### Force reload if stuck:
```bash
sudo launchctl unload -w /Library/LaunchDaemons/com.local.*.plist
sudo launchctl load -w /Library/LaunchDaemons/com.local.*.plist
```

### Remove services completely:
```bash
sudo launchctl unload /Library/LaunchDaemons/com.local.*.plist
sudo rm /Library/LaunchDaemons/com.local.*.plist
```

## Notes
- Services automatically start on boot
- Chat server may take 2-5 minutes to load the model
- Embedding server starts first to reduce system load during startup
- Both services run as your user account, not root 
