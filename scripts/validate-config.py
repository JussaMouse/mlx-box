#!/usr/bin/env python3
"""Validate config/settings.toml for required services and port sanity."""

from __future__ import annotations

import sys
from pathlib import Path
import tomllib

REQUIRED_SERVICES = [
    "router",
    "fast",
    "thinking",
    "embedding",
    "ocr",
    "tts",
    "whisper",
]


def main() -> int:
    path = Path("config/settings.toml")
    if not path.exists():
        print("❌ config/settings.toml not found")
        return 1

    cfg = tomllib.loads(path.read_text())
    services = cfg.get("services", {})

    errors: list[str] = []

    ports_seen: dict[int, str] = {}

    for name in REQUIRED_SERVICES:
        svc = services.get(name)
        if not svc:
            errors.append(f"Missing [services.{name}] section")
            continue

        for key in ("port", "backend_port", "model"):
            if key not in svc:
                errors.append(f"[services.{name}] missing '{key}'")

        for key in ("port", "backend_port"):
            if key in svc:
                port = int(svc[key])
                if port < 1 or port > 65535:
                    errors.append(f"[services.{name}] {key} out of range: {port}")
                if port in ports_seen:
                    errors.append(f"Port collision: {port} used by {ports_seen[port]} and services.{name}.{key}")
                else:
                    ports_seen[port] = f"services.{name}.{key}"

    if errors:
        print("❌ Config validation failed:")
        for err in errors:
            print(f"  - {err}")
        return 1

    print("✅ config/settings.toml looks good")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
