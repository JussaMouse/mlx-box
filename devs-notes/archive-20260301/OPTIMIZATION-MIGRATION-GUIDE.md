# MLX-Box Stack Migration Guide (Qwen3.5 + Voice Stack)

**Last updated**: 2026-03-01

This guide aligns a running system to the model/port stack defined in
`devs-notes/MLX-BOX-MODEL-STACK.md`.

## 1) Update Config

Update `config/settings.toml` and `config/settings.toml.example` to the new stack:

- Router: `mlx-community/Qwen3-0.6B-4bit` on `8080 → 8090`
- Fast: `mlx-community/Qwen3.5-35B-A3B-4bit` on `8081 → 8091`
- Thinking: `mlx-community/Qwen3.5-122B-A10B-4bit` on `8083 → 8093`
- Embedding: `Qwen/Qwen3-Embedding-8B` on `8084 → 8094`
- OCR: `mlx-community/olmOCR-2-7B-1025-mlx-8bit` on `8085 → 8095`
- TTS: `Qwen3-TTS-12Hz-0.6B-CustomVoice` on `8086 → 8096`
- Whisper: `small.en` on `8087 → 8097`

Also set modes for VLM-backed tiers:
- `services.fast.mode = "multimodal"`
- `services.thinking.mode = "multimodal"`

## 2) Update Dependencies

Install/refresh the isolated thinking venv (required for Qwen3.5-122B VLM):

```bash
cd models
/opt/homebrew/bin/python3.12 -m venv venvs/thinking
venvs/thinking/bin/python -m pip install -r models/requirements-thinking.txt
```

Install/refresh the voice stack (TTS + Whisper):

```bash
cd models/voice
poetry install
```

## 3) Reinstall LaunchDaemons

```bash
cd models
sudo ./startup-services-install.sh
```

## 4) Smoke Test

```bash
./test-services.sh
```

## 5) Monitor

```bash
./scripts/monitor-memory.sh
```

## Notes

- Qwen3.5 models include native thinking. Use `thinking_budget` to control it.
- `filter_reasoning = true` keeps responses clean without reducing quality.
- Multimodal Qwen3.5-122B requires `mlx-vlm[torch]` (torch + torchvision) in the thinking venv.
