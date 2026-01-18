#!/usr/bin/env python3
"""
OpenAI-compatible Vision Chat server for olmOCR on MLX.

This service is intentionally separate from the text-only mlx-lm tiers:
- Own port/logs/launchd label
- OpenAI /v1 endpoints (so OpenAI SDK clients can point at it)

Backend: mlx-vlm directly (stateless per request).

Why:
We observed output contamination across independent HTTP requests when using
mlx-openai-server for multimodal OCR (previous image text bleeding into the
next response). This implementation avoids retaining any per-request state.
"""

import base64
import logging
import re
import sys
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import tomlkit
import uvicorn


def load_config():
    """Load settings from the TOML config file."""
    try:
        config_path = Path(__file__).parent.parent / "config" / "settings.toml"
        with open(config_path, "r") as f:
            return tomlkit.load(f)
    except FileNotFoundError:
        print("❌ Configuration file 'config/settings.toml' not found.", file=sys.stderr)
        print(
            "   Please copy 'config/settings.toml.example' to 'config/settings.toml' and customize it.",
            file=sys.stderr,
        )
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error loading configuration: {e}", file=sys.stderr)
        sys.exit(1)


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

config = load_config()
server_config = config.get("server", {})
ocr_config = config.get("services", {}).get("ocr", {})

HOST = server_config.get("host", "127.0.0.1")
PORT = int(ocr_config.get("port", 8085))
MODEL_ID = ocr_config.get("model")

DEFAULT_MAX_TOKENS = int(ocr_config.get("max_tokens", 1024))
DEFAULT_TEMPERATURE = float(ocr_config.get("temperature", 0.0))

_model = None
_processor = None


def _parse_data_url_image(data_url: str) -> bytes:
    m = re.match(r"^data:image/[^;]+;base64,(.*)$", data_url, flags=re.DOTALL)
    if not m:
        raise ValueError("Only data:image/*;base64,... URLs are supported")
    return base64.b64decode(m.group(1))


def _extract_prompt_and_image(messages: List[Dict[str, Any]]) -> tuple[str, bytes]:
    if not messages:
        raise ValueError("messages must not be empty")

    user_msgs = [m for m in messages if m.get("role") == "user"]
    msg = user_msgs[-1] if user_msgs else messages[-1]

    content = msg.get("content")
    if isinstance(content, str):
        raise ValueError("Expected vision-style message content array; got string content")
    if not isinstance(content, list):
        raise ValueError("Expected message.content to be a list of parts")

    text_parts: List[str] = []
    image_bytes: Optional[bytes] = None

    for part in content:
        if not isinstance(part, dict):
            continue
        ptype = part.get("type")
        if ptype == "text":
            t = part.get("text")
            if isinstance(t, str) and t.strip():
                text_parts.append(t.strip())
        elif ptype == "image_url":
            url = (part.get("image_url") or {}).get("url")
            if isinstance(url, str) and url.startswith("data:") and image_bytes is None:
                image_bytes = _parse_data_url_image(url)

    if image_bytes is None:
        raise ValueError("No image_url data URL provided in message content")

    prompt = "\n".join(text_parts).strip()
    if not prompt:
        prompt = "Extract all visible text from this image. Return ONLY the extracted text."

    return prompt, image_bytes


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _model, _processor

    if not MODEL_ID:
        logger.error("❌ OCR model not configured under [services.ocr] in settings.toml")
        yield
        return

    try:
        import mlx_vlm
    except Exception as e:
        logger.error(f"❌ mlx-vlm not installed/available: {e}")
        yield
        return

    logger.info(f"Loading OCR VLM: {MODEL_ID}")
    try:
        _model, _processor = mlx_vlm.load(MODEL_ID)
        logger.info("✅ OCR model loaded")
    except Exception as e:
        logger.exception(f"❌ Failed to load OCR model: {e}")
        _model, _processor = None, None

    yield
    logger.info("Shutting down OCR server")


app = FastAPI(
    title="olmOCR Vision Chat Server",
    version="1.0.0",
    lifespan=lifespan,
)


class ChatCompletionRequest(BaseModel):
    model: Optional[str] = None
    messages: List[Dict[str, Any]]
    max_tokens: Optional[int] = None
    temperature: Optional[float] = None
    stream: Optional[bool] = False


@app.get("/v1/models")
async def list_models():
    if not MODEL_ID:
        raise HTTPException(status_code=503, detail="OCR model not configured")
    return {
        "object": "list",
        "data": [{"id": MODEL_ID, "object": "model", "created": 1677610602, "owned_by": "mlx-box"}],
    }


@app.post("/v1/chat/completions")
async def chat_completions(req: ChatCompletionRequest):
    if _model is None or _processor is None:
        raise HTTPException(status_code=503, detail="OCR model not loaded")

    try:
        prompt, image_bytes = _extract_prompt_and_image(req.messages)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    max_tokens = int(req.max_tokens) if req.max_tokens is not None else DEFAULT_MAX_TOKENS
    temperature = float(req.temperature) if req.temperature is not None else DEFAULT_TEMPERATURE

    with tempfile.NamedTemporaryFile(delete=True, suffix=".png") as f:
        f.write(image_bytes)
        f.flush()

        try:
            import mlx_vlm

            # Try to apply a chat template that includes image placeholders.
            try:
                prompt_str = mlx_vlm.apply_chat_template(
                    _processor,
                    getattr(_model, "config", {}),
                    [{"role": "user", "content": prompt}],
                    add_generation_prompt=True,
                    num_images=1,
                )
            except Exception:
                prompt_str = prompt

            result = mlx_vlm.generate(
                _model,
                _processor,
                prompt_str,
                image=f.name,
                temperature=temperature,
                max_tokens=max_tokens,
                verbose=False,
            )

            content = getattr(result, "text", None) or getattr(result, "output_text", None) or str(result)
        except Exception as e:
            logger.exception(f"OCR generation failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    return {
        "id": "chatcmpl-olmocr",
        "object": "chat.completion",
        "created": 0,
        "model": req.model or MODEL_ID,
        "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


@app.get("/health")
async def health():
    return {"status": "healthy" if _model is not None else "degraded", "model": MODEL_ID, "model_loaded": _model is not None}


def main():
    if not MODEL_ID:
        logger.error("OCR model name not configured. Exiting.")
        raise SystemExit(1)
    uvicorn.run(app, host=HOST, port=PORT)


if __name__ == "__main__":
    main()

