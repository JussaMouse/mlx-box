#!/usr/bin/env python3
"""
OpenAI-compatible Whisper (STT) server for MLX.

Endpoint:
- POST /v1/audio/transcriptions (multipart/form-data, OpenAI-style)
- GET  /v1/models
"""

import inspect
import logging
import os
import sys
import tempfile
from pathlib import Path
from typing import Optional
import shutil

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
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
    candidates = []

    env_path = os.environ.get("MLX_BOX_CONFIG")
    if env_path:
        candidate = Path(env_path).expanduser()
        candidates.append(candidate)
        if candidate.exists():
            return candidate

    env_root = os.environ.get("MLX_BOX_ROOT")
    if env_root:
        candidate = Path(env_root).expanduser() / "config" / "settings.toml"
        candidates.append(candidate)
        if candidate.exists():
            return candidate

    script_path = Path(__file__).resolve()
    for parent in [script_path.parent, *script_path.parents]:
        candidate = parent / "config" / "settings.toml"
        candidates.append(candidate)
        if candidate.exists():
            return candidate

    cwd = Path.cwd().resolve()
    for parent in [cwd, *cwd.parents]:
        candidate = parent / "config" / "settings.toml"
        candidates.append(candidate)
        if candidate.exists():
            return candidate

    attempted = "\n".join(f"   - {c}" for c in candidates)
    raise FileNotFoundError(f"config/settings.toml not found. Tried:\n{attempted}")


def load_config():
    """Load settings from the TOML config file."""
    load_env_file()
    try:
        config_path = resolve_config_path()
        logger.info(f"✅ Using config: {config_path}")
        with open(config_path, "r") as f:
            return tomlkit.load(f)
    except FileNotFoundError:
        print("❌ Configuration file 'config/settings.toml' not found.", file=sys.stderr)
        print(f"   MLX_BOX_CONFIG={os.environ.get('MLX_BOX_CONFIG')}", file=sys.stderr)
        print(f"   MLX_BOX_ROOT={os.environ.get('MLX_BOX_ROOT')}", file=sys.stderr)
        print(f"   CWD={Path.cwd().resolve()}", file=sys.stderr)
        print("   Please copy 'config/settings.toml.example' to 'config/settings.toml' and customize it.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error loading configuration: {e}", file=sys.stderr)
        sys.exit(1)


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

config = load_config()
server_config = config.get("server", {})
whisper_config = config.get("services", {}).get("whisper", {})

HOST = server_config.get("host", "127.0.0.1")
PORT = int(whisper_config.get("backend_port") or whisper_config.get("port", 8087))
MODEL_ID = whisper_config.get("model")
DEFAULT_LANGUAGE = whisper_config.get("language")


def resolve_model_id(model_id: str) -> str:
    """Resolve short model names to MLX community repos.

    If a full HF repo is provided, it is used directly.
    """
    if not model_id:
        return model_id

    model_id = model_id.strip()
    if "/" in model_id:
        return model_id

    mapping = {
        "small.en": "mlx-community/whisper-small.en-4bit",
        "medium.en": "mlx-community/whisper-medium.en-4bit",
        "turbo": "mlx-community/whisper-large-v3-turbo",
        "large-v3-turbo": "mlx-community/whisper-large-v3-turbo",
    }
    return mapping.get(model_id, f"mlx-community/whisper-{model_id}-4bit")


def prepare_whisper_model_path(model_id: str) -> str:
    """Ensure model files are in the expected MLX layout."""
    if not model_id:
        return model_id

    model_path = Path(model_id)
    if model_path.exists():
        return str(model_path)

    try:
        from huggingface_hub import snapshot_download
    except Exception:
        return model_id

    model_path = Path(snapshot_download(repo_id=model_id))

    # mlx_whisper expects weights.safetensors or weights.npz.
    # Some repos provide model.safetensors; link/copy it into place.
    model_safetensors = model_path / "model.safetensors"
    weights_safetensors = model_path / "weights.safetensors"
    if model_safetensors.exists() and not weights_safetensors.exists():
        try:
            weights_safetensors.symlink_to(model_safetensors.name)
        except Exception:
            try:
                shutil.copyfile(model_safetensors, weights_safetensors)
            except Exception:
                pass

    return str(model_path)


def build_transcribe_kwargs(**kwargs):
    """Filter kwargs to match mlx_whisper.transcribe signature."""
    import mlx_whisper

    sig = inspect.signature(mlx_whisper.transcribe)
    allowed = set(sig.parameters.keys())
    return {k: v for k, v in kwargs.items() if k in allowed and v is not None}


app = FastAPI(title="MLX Whisper STT", version="1.0.0")


@app.get("/v1/models")
async def list_models():
    if not MODEL_ID:
        raise HTTPException(status_code=503, detail="Whisper model not configured")
    return {
        "object": "list",
        "data": [{"id": MODEL_ID, "object": "model", "created": 1677610602, "owned_by": "mlx-box"}],
    }


@app.post("/v1/audio/transcriptions")
async def transcribe_audio(
    file: UploadFile = File(...),
    model: Optional[str] = Form(None),
    language: Optional[str] = Form(None),
    prompt: Optional[str] = Form(None),
    response_format: Optional[str] = Form("json"),
    temperature: Optional[float] = Form(None),
    task: Optional[str] = Form(None),
    word_timestamps: Optional[bool] = Form(False),
):
    if not MODEL_ID:
        raise HTTPException(status_code=503, detail="Whisper model not configured")

    try:
        import mlx_whisper
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"mlx-whisper is not available: {e}")

    if not file.filename:
        raise HTTPException(status_code=400, detail="Missing audio file")

    model_to_use = resolve_model_id(model or MODEL_ID)
    model_path = prepare_whisper_model_path(model_to_use)
    language = language or DEFAULT_LANGUAGE

    suffix = Path(file.filename).suffix or ".wav"
    with tempfile.NamedTemporaryFile(delete=True, suffix=suffix) as tmp:
        contents = await file.read()
        if not contents:
            raise HTTPException(status_code=400, detail="Empty audio file")
        tmp.write(contents)
        tmp.flush()

        kwargs = build_transcribe_kwargs(
            path_or_hf_repo=model_path,
            language=language,
            task=task,
            temperature=temperature,
            initial_prompt=prompt,
            word_timestamps=word_timestamps,
        )

        try:
            result = mlx_whisper.transcribe(tmp.name, **kwargs)
        except Exception as e:
            logger.exception("Whisper transcription failed")
            raise HTTPException(status_code=500, detail=str(e))

    if not isinstance(result, dict):
        return JSONResponse({"text": str(result)})

    if response_format in ("verbose_json", "json"):
        return JSONResponse(result)

    return {"text": result.get("text", "")}


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "model": MODEL_ID,
        "resolved_model": resolve_model_id(MODEL_ID) if MODEL_ID else None,
    }


if __name__ == "__main__":
    if not MODEL_ID:
        logger.error("Whisper model not configured. Exiting.")
    else:
        uvicorn.run(app, host=HOST, port=PORT, loop="asyncio")
