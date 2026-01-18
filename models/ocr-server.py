#!/usr/bin/env python3
"""
OpenAI-compatible Vision Chat server for olmOCR on MLX.

This service is intentionally separate from the text-only mlx-lm tiers:
- Own port/logs/launchd label
- OpenAI /v1 endpoints (so OpenAI SDK clients can point at it)

Backend: mlx-openai-server (multimodal) which uses mlx-vlm under the hood.
"""

import subprocess
import sys
from pathlib import Path
import importlib.util

import tomlkit


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


def main():
    config = load_config()
    server_config = config.get("server", {})
    ocr_config = config.get("services", {}).get("ocr", {})

    host = server_config.get("host", "127.0.0.1")
    port = int(ocr_config.get("port", 8085))
    model_id = ocr_config.get("model")

    # Optional knobs (passed through if present)
    context_length = ocr_config.get("context_length")
    # Default to single-worker to avoid any potential cross-request mixing bugs
    # in multimodal pipelines. You can raise this once stable.
    max_concurrency = ocr_config.get("max_concurrency", 1)

    if not model_id:
        print("❌ OCR model not configured under [services.ocr] in settings.toml", file=sys.stderr)
        sys.exit(1)

    if importlib.util.find_spec("app.main") is None:
        print("❌ Missing dependency: mlx-openai-server", file=sys.stderr)
        print("   Install it in models/: poetry add mlx-openai-server", file=sys.stderr)
        sys.exit(1)

    # mlx-openai-server uses the module path "app.main" for its CLI entrypoint.
    # We run it as a subprocess so launchd can manage this process directly.
    cmd = [
        sys.executable,
        "-m",
        "app.main",
        "launch",
        "--model-path",
        model_id,
        "--model-type",
        "multimodal",
        "--host",
        host,
        "--port",
        str(port),
    ]

    if context_length is not None:
        cmd.extend(["--context-length", str(int(context_length))])

    if max_concurrency is not None:
        cmd.extend(["--max-concurrency", str(int(max_concurrency))])

    print(f"🚀 Starting olmOCR OpenAI server on http://{host}:{port}/v1")
    print(f"📦 Model: {model_id}")
    print(f"Running: {' '.join(cmd)}")

    try:
        raise SystemExit(subprocess.call(cmd))
    except KeyboardInterrupt:
        raise SystemExit(0)


if __name__ == "__main__":
    main()

