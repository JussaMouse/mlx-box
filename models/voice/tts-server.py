#!/usr/bin/env python3
"""
OpenAI-compatible TTS server for Qwen3-TTS on MLX.

Endpoint:
- POST /v1/audio/speech
- GET  /v1/models
"""

import io
import logging
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
import tomlkit
import uvicorn


def load_env_file():
    env_path = Path(__file__).resolve().parents[2] / "config" / "settings.env"
    if not env_path.exists():
        return
    try:
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value
    except Exception as e:
        print(f"⚠️  Failed to read settings.env: {e}", file=sys.stderr)


def resolve_config_path() -> Path:
    env_path = os.environ.get("MLX_BOX_CONFIG")
    if env_path:
        candidate = Path(env_path).expanduser()
        if candidate.exists():
            return candidate

    env_root = os.environ.get("MLX_BOX_ROOT")
    if env_root:
        candidate = Path(env_root).expanduser() / "config" / "settings.toml"
        if candidate.exists():
            return candidate

    candidate = Path(__file__).resolve().parents[2] / "config" / "settings.toml"
    if candidate.exists():
        return candidate

    cwd = Path.cwd().resolve()
    for parent in [cwd, *cwd.parents]:
        candidate = parent / "config" / "settings.toml"
        if candidate.exists():
            return candidate

    raise FileNotFoundError("config/settings.toml not found")


def load_config():
    """Load settings from the TOML config file."""
    load_env_file()
    os.environ.setdefault("NUMBA_CACHE_DIR", str(Path.home() / "Library" / "Caches" / "numba"))
    try:
        config_path = resolve_config_path()
        with open(config_path, "r") as f:
            return tomlkit.load(f)
    except FileNotFoundError:
        print("❌ Configuration file 'config/settings.toml' not found.", file=sys.stderr)
        print("   Please copy 'config/settings.toml.example' to 'config/settings.toml' and customize it.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error loading configuration: {e}", file=sys.stderr)
        sys.exit(1)


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

config = load_config()
server_config = config.get("server", {})
tts_config = config.get("services", {}).get("tts", {})

HOST = server_config.get("host", "127.0.0.1")
PORT = int(tts_config.get("backend_port") or tts_config.get("port", 8086))
MODEL_ID = tts_config.get("model")
DEFAULT_VOICE = tts_config.get("default_voice", "Chelsie")
DEFAULT_LANGUAGE = tts_config.get("language", "Auto")
ATTN_IMPL = tts_config.get("attn_implementation")

_model = None


def resolve_tts_model_id(model_id: Optional[str]) -> Optional[str]:
    if not model_id:
        return model_id
    model_id = model_id.strip()
    if "/" in model_id:
        return model_id
    return f"Qwen/{model_id}"


def _select_device():
    try:
        import torch
    except Exception:
        return "cpu", None

    if torch.backends.mps.is_available():
        return "mps", torch.float32
    if torch.cuda.is_available():
        return "cuda:0", torch.bfloat16
    return "cpu", torch.float32


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _model

    if not MODEL_ID:
        logger.error("❌ TTS model not configured under [services.tts] in settings.toml")
        yield
        return

    try:
        import torch
        import soundfile as sf  # noqa: F401
        from qwen_tts import Qwen3TTSModel
    except Exception as e:
        logger.error(f"❌ qwen-tts dependency missing: {e}")
        yield
        return

    device, dtype = _select_device()
    resolved_model_id = resolve_tts_model_id(MODEL_ID)
    if resolved_model_id != MODEL_ID:
        logger.info(f"Resolved TTS model id: {MODEL_ID} -> {resolved_model_id}")
    logger.info(f"Loading Qwen3-TTS model: {resolved_model_id}")
    logger.info(f"Device: {device}")

    try:
        model_kwargs = {}
        if dtype is not None:
            model_kwargs["torch_dtype"] = dtype
        if ATTN_IMPL:
            model_kwargs["attn_implementation"] = ATTN_IMPL
        hf_token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_HUB_TOKEN")
        if hf_token:
            model_kwargs["token"] = hf_token

        _model = Qwen3TTSModel.from_pretrained(
            resolved_model_id,
            device_map=device,
            **model_kwargs,
        )
        logger.info("✅ TTS model loaded")
    except Exception as e:
        logger.exception(f"❌ Failed to load TTS model: {e}")
        _model = None

    yield
    logger.info("Shutting down TTS server")


app = FastAPI(title="Qwen3 TTS Server", version="1.0.0", lifespan=lifespan)


class SpeechRequest(BaseModel):
    model: Optional[str] = None
    input: str
    voice: Optional[str] = None
    language: Optional[str] = None
    instruct: Optional[str] = ""
    response_format: Optional[str] = "wav"
    mode: Optional[str] = "custom_voice"
    stream: Optional[bool] = False


@app.get("/v1/models")
async def list_models():
    if not MODEL_ID:
        raise HTTPException(status_code=503, detail="TTS model not configured")
    return {
        "object": "list",
        "data": [{"id": MODEL_ID, "object": "model", "created": 1677610602, "owned_by": "qwen"}],
    }


@app.post("/v1/audio/speech")
async def text_to_speech(req: SpeechRequest):
    if _model is None:
        raise HTTPException(status_code=503, detail="TTS model not loaded")

    text = (req.input or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="input must not be empty")

    voice = req.voice or DEFAULT_VOICE
    language = req.language or DEFAULT_LANGUAGE
    instruct = req.instruct or ""

    try:
        import soundfile as sf
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"soundfile dependency missing: {e}")

    mode = (req.mode or "custom_voice").lower()
    try:
        if mode == "voice_design":
            wavs, sr = _model.generate_voice_design(text=text, language=language, instruct=instruct)
        else:
            wavs, sr = _model.generate_custom_voice(text=text, language=language, speaker=voice, instruct=instruct)
    except Exception as e:
        logger.exception("TTS generation failed")
        raise HTTPException(status_code=500, detail=str(e))

    if not wavs:
        raise HTTPException(status_code=500, detail="TTS generation returned empty audio")

    buffer = io.BytesIO()
    sf.write(buffer, wavs[0], sr, format="WAV")
    buffer.seek(0)

    return Response(content=buffer.getvalue(), media_type="audio/wav")


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "model": MODEL_ID,
        "device": _select_device()[0],
    }


if __name__ == "__main__":
    if not MODEL_ID:
        logger.error("TTS model not configured. Exiting.")
    else:
        uvicorn.run(app, host=HOST, port=PORT, loop="asyncio")
