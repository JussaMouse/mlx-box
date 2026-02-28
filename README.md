# mlx-box

Nginx + firewall + launchd services for a local, OpenAI-compatible MLX stack on macOS.

**What you get**
- Nginx TLS reverse proxy (certbot webroot)
- pf firewall (only SSH/80/443)
- LaunchDaemons for 7 services (router/fast/thinking/embedding/OCR/TTS/Whisper)
- Auth proxy on frontend ports, backend MLX ports bound to localhost
- Ops scripts for install, updates, smoke tests, reports

---

## Quick start
1. Copy and edit config:
```sh
cp config/settings.toml.example config/settings.toml
cp config/settings.env.example config/settings.env
hx config/settings.toml
hx config/settings.env
```
2. Point DNS to your server and forward ports 80/443 + SSH.
3. Install:
```sh
chmod +x install.sh
./install.sh
```
4. Test services:
```sh
scripts/test-services.sh
```

Optional: add a Hugging Face token to speed model downloads in `config/settings.env`:
```sh
HF_TOKEN=hf_...
```
Then restart services:
```sh
scripts/restart-all-services.sh
```

---

## Services and ports
Frontend ports (auth) → backend ports (MLX):

```
router   8080 → 8090
fast     8081 → 8091
thinking 8083 → 8093
embedding 8084 → 8094
ocr      8085 → 8095
tts      8086 → 8096
whisper  8087 → 8097
```

Default models (see `config/settings.toml`):
- router: `mlx-community/Qwen3-0.6B-4bit`
- fast: `mlx-community/Qwen3.5-35B-A3B-4bit`
- thinking: `nightmedia/Qwen3.5-122B-A10B-Text-mxfp4-mlx`
- embedding: `Qwen/Qwen3-Embedding-8B`
- ocr: `mlx-community/olmOCR-2-7B-1025-mlx-8bit`
- tts: `Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice`
- whisper: `mlx-community/whisper-small.en-4bit`

---

## Config overview
`config/settings.env` drives installation and system config:
- `DOMAIN_NAME`, `LETSENCRYPT_EMAIL`, `SSH_PORT`
- `ALLOWED_IPS` (optional nginx allowlist)
- `HF_TOKEN` (optional HF download auth)

`config/settings.toml` drives runtime:
- `[services.*]` ports, backend ports, models
- `[server] api_key` or `api_keys` for auth

---

## Auth proxy layer
Clients hit the frontend ports with an API key, which proxies to backend MLX services.

```sh
curl http://localhost:8081/v1/models \
  -H "Authorization: Bearer your-api-key"
```

If `api_key` and `api_keys` are empty, auth is disabled. Only do this for strictly localhost use.

---

## Voice stack (TTS + Whisper)
Voice services live in `models/voice` with a **separate Poetry environment** to avoid `transformers` conflicts between `qwen-tts` and `mlx-openai-server`. They are still launched by the same installer so there is one place to manage services and launchd plists.

Endpoints:
- TTS: `POST /v1/audio/speech` on `8086`
- Whisper: `POST /v1/audio/transcriptions` on `8087`

`ffmpeg` and `sox` are required; the installer will auto-install them via Homebrew.

---

## Common operations
Install/reinstall:
```sh
./install.sh
```

Restart all services:
```sh
scripts/restart-all-services.sh
```

Update models by editing `config/settings.toml` and re-running the installer:
```sh
./install.sh
```

Validate config:
```sh
scripts/validate-config.py
```

Generate a system report:
```sh
scripts/generate_system_report.sh
```

Security audit:
```sh
scripts/security-audit-mlx.sh
```

---

## Troubleshooting
- Check logs:
```sh
tail -f ~/Library/Logs/com.mlx-box.*/stderr.log
```
- If fast/thinking return “Backend service unavailable”, the model is probably still downloading. Set `HF_TOKEN` and restart services.
- Whisper errors about `ffmpeg` mean the dependency is missing; rerun `./install.sh` or install with `brew install ffmpeg sox`.
- `scripts/test-services.sh` is the quickest health check.

---

## Updating the repo
```sh
git pull --rebase
./install.sh
scripts/test-services.sh
```

---

## Architecture (short)
- pf firewall allows SSH/80/443 only.
- Nginx terminates TLS and proxies requests to localhost services.
- LaunchDaemons run backend MLX servers and auth proxies.

---

## Scripts reference
- `scripts/test-services.sh`: smoke tests all endpoints
- `scripts/restart-all-services.sh`: restart launchd services
- `scripts/benchmark-services.sh`: quick latency and throughput checks
- `scripts/generate_system_report.sh`: captures a full system report under `reports/`
- `scripts/collect_system_info.sh`: writes `config/system-info.env`
- `scripts/monitor-memory.sh`: RAM/swap usage overview
- `scripts/security-audit-mlx.sh`: permission/exposure checks

Additional archival notes live under `devs-notes/`.
