# MLX-Box Update: Qwen 3.5 + Voice Stack Refresh

## Goal
Update the **fast** and **thinking** LLM models to Qwen 3.5, refresh TTS/Whisper models in MLX‑Box, and move the working directory to `~/server/mlx-box`.

## Preconditions
- Confirm which Qwen 3.5 model variants are available and supported by MLX‑Box.
- Decide the exact fast vs thinking pair (e.g., smaller vs larger Qwen 3.5).
- Confirm the target TTS and Whisper versions already supported on Apple Silicon.

## Work plan (minimal)
1) **Repo location**: move working dir to `~/server/mlx-box` and confirm repo state.
2) **Model inventory**: list current fast/thinking models in config and runtime.
3) **LLM update**: swap model IDs to Qwen 3.5 (fast + thinking).
4) **Voice stack update**: add/refresh required TTS and Whisper models.
5) **Smoke test**: small prompt through fast/thinking + short STT/TTS loop.
6) **Docs**: update any model references in configs or notes.

## Model selection guidance
- **Fast**: smaller Qwen 3.5 variant for quick responses.
- **Thinking**: larger Qwen 3.5 variant for reasoning/tool usage.
- **TTS**: Qwen3‑TTS 0.6B + 1.7B CustomVoice as defaults.
- **STT**: Whisper `small.en` for latency; `medium.en` if accuracy needed.

## Validation checks
- End‑to‑end latency stays within interactive targets.
- Speech quality is stable on at least 2 reference voices.
- Model load times acceptable after cold start.

## Notes
- Treat model IDs and file names as configuration, not hard‑coded logic.
- Keep a rollback path in case the new models regress latency.

## Current State (2026-03-01)
- Fast tier: `mlx-community/Qwen3.5-35B-A3B-4bit`
- Fast mode: `multimodal` (mlx-vlm) via `models/vlm-chat-server.py`
- Thinking tier: `mlx-community/Qwen3.5-122B-A10B-4bit`
- Thinking mode: `multimodal` (mlx-vlm) via `models/vlm-chat-server.py`
- Router: `mlx-community/Qwen3-0.6B-4bit`
- Added `/v1/models` proxy override so each service only reports its configured model.
- If HF downloads stall on Xet, set `HF_HUB_DISABLE_XET=1` in `config/settings.env`.

## Known Issue: Thinking Output Gibberish
- Root cause: `qwen3_5_moe` decoding under stock `mlx-lm` yields garbage output.
- Workaround (recommended): run thinking in an isolated venv with newer `mlx/ mlx-lm`.
- See README section “Thinking backend isolated env (Qwen3.5-122B)”.

## Known Issue: VLM Processor Errors
- Symptom: `Failed to load VLM model` or `torchvision is not available`.
- Fix: install the thinking venv deps (includes `mlx-vlm[torch]`), then restart thinking.
