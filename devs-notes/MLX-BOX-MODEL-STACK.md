# MLX-Box Model Stack (2026)

**System**: Apple Silicon, 192 GB unified RAM
**Last updated**: 2026-03-01

---

## Port Map

| Port | Backend | Service |
|------|---------|---------|
| 8080 | 8090 | Router |
| 8081 | 8091 | Fast |
| 8083 | 8093 | Thinking |
| 8084 | 8094 | Embedding |
| 8085 | 8095 | OCR |
| 8086 | 8096 | TTS |
| 8087 | 8097 | Whisper (STT) |

---

## Core LLM Services

| Tier | Model | RAM | Notes |
|------|-------|-----|-------|
| **Router** | `mlx-community/Qwen3-0.6B-4bit` | ~0.5 GB | Complexity classification only; tiny is correct here |
| **Fast** | `mlx-community/Qwen3.5-35B-A3B-4bit` | ~20 GB | Upgrade from Qwen3-30B-A3B; same 3B active params, better architecture |
| **Thinking** | `mlx-community/Qwen3.5-122B-A10B-4bit` | ~70 GB | 10B active params; multimodal VLM checkpoint |
| **Embedding** | `Qwen/Qwen3-Embedding-8B` | ~10 GB | Unchanged; already optimal |

### Thinking Tier — Important Architecture Note

Qwen3.5 has **thinking built in for all models** — no separate `-Thinking` variant needed.
Every Qwen3.5 model natively outputs `<think>...</think>` blocks.

- **Thinking tier**: enable extended thinking (full budget)
- **Fast tier**: disable thinking or set a very low budget (e.g. 512 tokens)
- **Multimodal**: install `mlx-vlm[torch]` in the thinking venv (torch + torchvision required)

### Temporary Fallback (if 122B VLM is unavailable)

If `mlx-community/Qwen3.5-122B-A10B-4bit` is unavailable or unstable:

```
mlx-community/Qwen3.5-27B-4bit  (~16 GB)
```

Dense 27B; still better than Qwen3-30B-A3B-Thinking on most tasks.

---

## Voice Stack (Voicebox)

### TTS — Qwen3-TTS (install in this order)

| Priority | Model | Notes |
|----------|-------|-------|
| 1st | `Qwen3-TTS-12Hz-0.6B-CustomVoice` | Fastest baseline; streaming-capable; start here |
| 2nd | `Qwen3-TTS-12Hz-1.7B-CustomVoice` | Higher fidelity; still streaming; best "wow" quality |
| 3rd | `Qwen3-TTS-12Hz-0.6B-Base` | Quick voice cloning from short reference audio |
| Optional | `Qwen3-TTS-12Hz-1.7B-VoiceDesign` | Text-described voices instead of cloning |

### STT — Whisper

| Priority | Model | Notes |
|----------|-------|-------|
| Default | `small.en` | Best latency/accuracy balance for English; start here |
| Upgrade | `medium.en` | Higher accuracy; still reasonable latency on this hardware |
| Speed mode | `turbo` | Fastest near-real-time; use if latency is king |

---

## OCR

| Model | RAM | Notes |
|-------|-----|-------|
| `mlx-community/olmOCR-2-7B-1025-mlx-8bit` | ~7 GB | max_concurrency = 1 |

---

## Memory Budget

```
Router    (Qwen3-0.6B-4bit):              ~0.5 GB
Fast      (Qwen3.5-35B-A3B-4bit):         ~20 GB
Thinking  (Qwen3.5-122B-A10B 4bit VLM):   ~70 GB
Embedding (Qwen3-Embedding-8B):           ~10 GB
OCR       (olmOCR-2-7B-8bit):              ~7 GB
TTS       (Qwen3-TTS-0.6B + 1.7B):        ~3 GB
STT       (Whisper small.en):              ~0.5 GB
─────────────────────────────────────────────────
Subtotal models:                           ~111 GB
OS + overhead:                             ~15 GB
KV cache / context buffer:                 ~15 GB
═════════════════════════════════════════════════
Total:                                    ~141 GB ✓
```

> Note: OCR and voice services aren't always loaded simultaneously with all LLM tiers.
> In practice the peak concurrent load is lower than the worst-case above.

---

## settings.toml Targets

```toml
[services.router]
port = 8080
backend_port = 8090
model = "mlx-community/Qwen3-0.6B-4bit"
max_tokens = 100
temperature = 0.1
top_p = 0.9

[services.fast]
port = 8081
backend_port = 8091
model = "mlx-community/Qwen3.5-35B-A3B-4bit"
mode = "multimodal"
max_tokens = 8192
temperature = 0.6
top_p = 0.92
frequency_penalty = 0.3
# Qwen3.5: thinking is always available; keep budget low for fast tier
thinking_budget = 0

[services.thinking]
port = 8083
backend_port = 8093
model = "mlx-community/Qwen3.5-122B-A10B-4bit"
mode = "multimodal"
max_tokens = 32768
thinking_budget = 16384
temperature = 0.2
top_p = 0.9

[services.embedding]
port = 8084
backend_port = 8094
model = "Qwen/Qwen3-Embedding-8B"
batch_size = 64
max_seq_length = 1024
quantization = true

[services.ocr]
port = 8085
backend_port = 8095
model = "mlx-community/olmOCR-2-7B-1025-mlx-8bit"
max_concurrency = 1

[services.tts]
port = 8086
backend_port = 8096
model = "Qwen3-TTS-12Hz-0.6B-CustomVoice"

[services.whisper]
port = 8087
backend_port = 8097
model = "small.en"
```

---

## Upgrade Watchlist

- `mlx-community/Qwen3.5-122B-A10B-4bit` — current thinking tier; keep the multimodal venv (`mlx-vlm[torch]`) healthy
- `mlx-community/Qwen3.5-397B-A17B-*` — 224 GB even at 4-bit; requires a dedicated box, not viable here
