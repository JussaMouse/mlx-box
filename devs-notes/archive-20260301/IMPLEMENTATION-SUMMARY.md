# Implementation Summary: Qwen3.5 + Voice Stack Refresh

**Date**: 2026-02-28

## ✅ What Changed

### 1) Model Stack + Port Map

- Router: `mlx-community/Qwen3-0.6B-4bit` on `8080 → 8090`
- Fast: `mlx-community/Qwen3.5-35B-A3B-4bit` on `8081 → 8091`
- Thinking: `mlx-community/Qwen3.5-122B-A10B-4bit` on `8083 → 8093`
- Embedding: `Qwen/Qwen3-Embedding-8B` on `8084 → 8094`
- OCR: `mlx-community/olmOCR-2-7B-1025-mlx-8bit` on `8085 → 8095`
- TTS: `Qwen3-TTS-12Hz-0.6B-CustomVoice` on `8086 → 8096`
- Whisper: `small.en` on `8087 → 8097`

### 2) New Services

- Added `models/voice/tts-server.py` (OpenAI-compatible `/v1/audio/speech`).
- Added `models/voice/whisper-server.py` (OpenAI-compatible `/v1/audio/transcriptions`).
- Auth proxy now supports binary responses (audio) and new services.
- LaunchDaemons updated to start TTS/Whisper backends and auth proxies.

### 3) Script Updates

- Config validation script: `scripts/validate-config.py`.
- `test-services.sh` now tests all 7 services, including TTS and Whisper.
- Benchmark, monitoring, and reporting scripts use config-driven ports.
- Restart script includes TTS/Whisper.

### 4) Docs & Examples

- Port map, model IDs, and examples updated across README and operational docs.
- `install.sh` now routes OpenAI audio endpoints to TTS/Whisper ports.

## ✅ Next Steps (Operator)

```bash
# Re-install launchd services
cd models
sudo ./startup-services-install.sh

# Validate config
python3 scripts/validate-config.py

# Smoke test all services
./test-services.sh
```

## Notes

- Qwen3.5 models include thinking by default; control it via `thinking_budget`.
- `filter_reasoning = true` keeps responses clean without reducing quality.
