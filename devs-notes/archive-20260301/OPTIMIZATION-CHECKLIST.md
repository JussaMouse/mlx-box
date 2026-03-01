# MLX-Box Optimization Checklist (128GB RAM)

This checklist tracks the **current model stack** and verifies the system matches
`devs-notes/MLX-BOX-MODEL-STACK.md`.

## ✅ Configuration Targets

- [ ] **Router Service**
  - [ ] Model: `mlx-community/Qwen3-0.6B-4bit`
  - [ ] `max_tokens = 100`
  - [ ] `temperature = 0.1`, `top_p = 0.9`

- [ ] **Fast Service (Qwen3.5-35B-A3B-4bit)**
  - [ ] Model: `mlx-community/Qwen3.5-35B-A3B-4bit`
  - [ ] `max_tokens = 8192`
  - [ ] `temperature = 0.6`, `top_p = 0.92`
  - [ ] `thinking_budget = 0`
  - [ ] `filter_reasoning = true`

- [ ] **Thinking Service (Qwen3.5-122B-A10B 4bit VLM)**
  - [ ] Model: `mlx-community/Qwen3.5-122B-A10B-4bit`
  - [ ] `max_tokens = 32768`
  - [ ] `thinking_budget = 16384`
  - [ ] `temperature = 0.2`, `top_p = 0.9`
  - [ ] `filter_reasoning = true`

- [ ] **Embedding Service (Qwen3-Embedding-8B)**
  - [ ] `batch_size = 64`
  - [ ] `max_seq_length = 1024`
  - [ ] `quantization = true`

- [ ] **OCR Service**
  - [ ] Model: `mlx-community/olmOCR-2-7B-1025-mlx-8bit`
  - [ ] `max_concurrency = 1`

- [ ] **TTS Service**
  - [ ] Model: `Qwen3-TTS-12Hz-0.6B-CustomVoice`
  - [ ] `default_voice = Chelsie`

- [ ] **Whisper Service**
  - [ ] Model: `small.en`

## ✅ Port Map

- Router: `8080` → `8090`
- Fast: `8081` → `8091`
- Thinking: `8083` → `8093`
- Embedding: `8084` → `8094`
- OCR: `8085` → `8095`
- TTS: `8086` → `8096`
- Whisper: `8087` → `8097`

## ✅ Testing & Monitoring

- [ ] **Config validation**
  ```bash
  python3 scripts/validate-config.py
  ```

- [ ] **Smoke test all services**
  ```bash
  ./test-services.sh
  ```

- [ ] **Benchmark core tiers**
  ```bash
  ./scripts/benchmark-services.sh
  ```

- [ ] **Monitor memory**
  ```bash
  ./scripts/monitor-memory.sh
  ```

- [ ] **Restart all services**
  ```bash
  sudo launchctl kickstart -k system/com.mlx-box.router
  sudo launchctl kickstart -k system/com.mlx-box.fast
  sudo launchctl kickstart -k system/com.mlx-box.thinking
  sudo launchctl kickstart -k system/com.mlx-box.embedding
  sudo launchctl kickstart -k system/com.mlx-box.ocr
  sudo launchctl kickstart -k system/com.mlx-box.tts
  sudo launchctl kickstart -k system/com.mlx-box.whisper
  ```

## ✅ Notes

- For Qwen3.5 models, thinking is **always available**; use `thinking_budget` to control it.
- `filter_reasoning = true` keeps responses clean while preserving reasoning quality.
