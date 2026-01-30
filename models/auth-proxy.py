#!/usr/bin/env python3
"""
Authentication Proxy for MLX Services
Validates API keys before forwarding requests to backend MLX servers.
"""

import sys
import argparse
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import FastAPI, Request, HTTPException, status
from fastapi.responses import StreamingResponse, JSONResponse
import httpx
import tomlkit


def load_config():
    """Load settings from the TOML config file."""
    try:
        config_path = Path(__file__).parent.parent / "config" / "settings.toml"
        with open(config_path, "r") as f:
            return tomlkit.load(f)
    except FileNotFoundError:
        print("❌ Configuration file 'config/settings.toml' not found.")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error loading configuration: {e}")
        sys.exit(1)


def create_auth_proxy(backend_port: int, api_key: Optional[str] = None):
    """Create FastAPI app that proxies requests with authentication."""
    app = FastAPI(title="MLX Auth Proxy")
    backend_url = f"http://127.0.0.1:{backend_port}"

    async def verify_api_key(request: Request) -> bool:
        """Verify the API key from Authorization header."""
        if not api_key:
            # No API key configured, allow all requests
            return True

        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return False

        token = auth_header[7:]  # Remove "Bearer " prefix
        return token == api_key

    @app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD", "PATCH"])
    async def proxy(path: str, request: Request):
        """Forward all requests to backend MLX server after validating auth."""
        # Verify API key
        if not await verify_api_key(request):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or missing API key",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Forward request to backend
        url = f"{backend_url}/{path}"
        headers = dict(request.headers)

        # Remove host header to avoid conflicts
        headers.pop("host", None)

        async with httpx.AsyncClient(timeout=300.0) as client:
            try:
                # Check if response should be streamed
                body = await request.body()

                response = await client.request(
                    method=request.method,
                    url=url,
                    headers=headers,
                    content=body,
                    params=request.query_params,
                )

                # Check if streaming response
                if "text/event-stream" in response.headers.get("content-type", ""):
                    async def stream_response():
                        async for chunk in response.aiter_bytes():
                            yield chunk

                    return StreamingResponse(
                        stream_response(),
                        status_code=response.status_code,
                        headers=dict(response.headers),
                        media_type=response.headers.get("content-type"),
                    )
                else:
                    # Return regular response
                    return JSONResponse(
                        content=response.json() if response.headers.get("content-type", "").startswith("application/json") else response.text,
                        status_code=response.status_code,
                        headers=dict(response.headers),
                    )

            except httpx.RequestError as e:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Backend service unavailable: {str(e)}",
                )

    return app


def main():
    """Main function to start the auth proxy."""
    parser = argparse.ArgumentParser(description="Start authentication proxy for MLX services")
    parser.add_argument("--service", choices=["router", "fast", "thinking", "embedding", "ocr"],
                        required=True, help="The service to proxy")
    parser.add_argument("--frontend-port", type=int, required=True,
                        help="The port this proxy will listen on")
    parser.add_argument("--backend-port", type=int, required=True,
                        help="The port the backend MLX service is running on")
    args = parser.parse_args()

    # Load configuration
    config = load_config()
    server_config = config.get("server", {})
    host = server_config.get("host", "127.0.0.1")

    # Get API key from config
    api_key = server_config.get("api_key")

    if api_key:
        print(f"🔐 Authentication enabled for {args.service} service")
    else:
        print(f"⚠️  WARNING: No API key configured - running without authentication")

    print(f"🚀 Starting auth proxy for {args.service.upper()} service")
    print(f"📍 Frontend: http://{host}:{args.frontend_port}")
    print(f"🔗 Backend: http://{host}:{args.backend_port}")
    print()

    # Create and run proxy
    app = create_auth_proxy(args.backend_port, api_key)

    uvicorn.run(
        app,
        host=host,
        port=args.frontend_port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
