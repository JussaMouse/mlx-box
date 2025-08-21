# Local AI Model Services - Management Guide

## Service Status
Check if services are running:
```bash
launchctl list | grep com.local
```

## Log Monitoring
View real-time logs:
```bash
# Embedding server logs
tail -f /var/log/embed-server.log
tail -f /var/log/embed-server-error.log

# Chat server logs  
tail -f /var/log/mlx-chat-server.log
tail -f /var/log/mlx-chat-server-error.log
```

## Service Management Commands

### Stop Services
```bash
sudo launchctl unload /Library/LaunchDaemons/com.local.embed-server.plist
sudo launchctl unload /Library/LaunchDaemons/com.local.mlx-chat-server.plist
```

### Start Services  
```bash
sudo launchctl load /Library/LaunchDaemons/com.local.embed-server.plist
sudo launchctl load /Library/LaunchDaemons/com.local.mlx-chat-server.plist
```

### Restart Services
```bash
# Stop both
sudo launchctl unload /Library/LaunchDaemons/com.local.embed-server.plist
sudo launchctl unload /Library/LaunchDaemons/com.local.mlx-chat-server.plist

# Start both (embedding first, then chat)
sudo launchctl load /Library/LaunchDaemons/com.local.embed-server.plist
sleep 30
sudo launchctl load /Library/LaunchDaemons/com.local.mlx-chat-server.plist
```

## Test Endpoints
After installation, test these endpoints (wait 2-5 minutes for startup):

### Check if services are responding:
```bash
# Test embedding server
curl http://127.0.0.1:8081/v1/models

# Test chat server  
curl http://127.0.0.1:8080/v1/models
```

### Test embedding functionality:
```bash
curl -X POST http://127.0.0.1:8081/v1/embeddings \
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
- **Embedding API**: http://127.0.0.1:8081/v1/models
- **Chat API**: http://127.0.0.1:8080/v1/models

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
