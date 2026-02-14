#!/usr/bin/env python3
"""
MLX Chat Server - Multi-Tier Architecture Support
Supports: Router, Fast, and Thinking service tiers
"""

import subprocess
import sys
import argparse
import time
import requests
from pathlib import Path
import tomlkit

# --- Configuration Loading ---
def load_config():
    """Load settings from the TOML config file."""
    try:
        config_path = Path(__file__).parent.parent / "config" / "settings.toml"
        with open(config_path, "r") as f:
            return tomlkit.load(f)
    except FileNotFoundError:
        print("❌ Configuration file 'config/settings.toml' not found.")
        print("   Please copy 'config/settings.toml.example' to 'config/settings.toml' and customize it.")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error loading configuration: {e}")
        sys.exit(1)

# --- End Configuration Loading ---


def check_mlx_available():
    """Check if MLX is available on this system"""
    try:
        import mlx
        import mlx_lm
        return True
    except ImportError:
        return False

def wait_for_server(host, port, timeout=300):
    """Wait for the server to become available"""
    print(f"Waiting for server at http://{host}:{port}...")
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        try:
            response = requests.get(f"http://{host}:{port}/v1/models", timeout=5)
            if response.status_code == 200:
                print("✅ Server is ready!")
                return True
        except requests.exceptions.RequestException:
            pass
        
        time.sleep(2)
    
    return False

def main():
    """Main function to start the MLX chat server"""
    parser = argparse.ArgumentParser(description="Start an MLX chat server for a specific tier")
    parser.add_argument("--service", choices=["router", "fast", "thinking"], default="fast",
                        help="The service tier to run (default: fast)")
    args = parser.parse_args()
    
    # Load configuration from settings.toml
    config = load_config()
    server_config = config.get("server", {})
    host = server_config.get("host", "127.0.0.1")
    
    # Get service-specific config
    service_name = args.service
    service_config = config.get("services", {}).get(service_name, {})
    
    if not service_config:
        print(f"❌ Configuration for service '{service_name}' not found in 'config/settings.toml'.")
        sys.exit(1)

    model_name = service_config.get("model")
    # Use backend_port if available (for auth proxy setup), otherwise use port
    port = service_config.get("backend_port") or service_config.get("port", 8080)
    max_tokens = service_config.get("max_tokens", 4096)

    # NEW: Model parameters for generation quality
    temperature = service_config.get("temperature")  # Default None (server decides)
    top_p = service_config.get("top_p")
    frequency_penalty = service_config.get("frequency_penalty")
    presence_penalty = service_config.get("presence_penalty")

    # Special config for thinking model (not used by CLI directly but good to track)
    thinking_budget = service_config.get("thinking_budget") 

    if not model_name:
        print(f"❌ Model name not specified for '{service_name}' in config.")
        sys.exit(1)

    # Check if MLX is available
    if not check_mlx_available():
        print("❌ MLX not available. Install with: poetry add mlx mlx-lm")
        sys.exit(1)
    
    print(f"🚀 Starting MLX server for Tier: {service_name.upper()}")
    print(f"📦 Model: {model_name}")
    print(f"📍 Address: http://{host}:{port}")
    print(f"🔄 This will download the model on first run if not cached.")
    print()
    
    # Build command for mlx_lm.server
    # Use patched server without uvloop for OpenAI SDK compatibility
    cmd = [sys.executable, "patched_mlx_server_no_uvloop.py"]

    cmd.extend([
        "--model", model_name,
        "--port", str(port),
        "--host", host,
        "--max-tokens", str(max_tokens)
    ])

    # Add optional generation parameters if specified in config
    if temperature is not None:
        cmd.extend(["--temp", str(temperature)])
    if top_p is not None:
        cmd.extend(["--top-p", str(top_p)])

    # Note: repetition_penalty and presence_penalty not supported by patched_mlx_server.py
    # These would need to be handled at the application level or added to the patched server
    
    # Add kv-cache-quant for larger models to save RAM
    # Apply to fast and thinking models (typically 30B+)
    # Note: Disabled again as it causes errors on server startup even with latest deps
    # if service_name in ["fast", "thinking"]:
    #      cmd.extend(["--kv-cache-quant", "8bit"])

    print(f"Running: {' '.join(cmd)}")
    print("=" * 50)
    
    # Start server process
    try:
        process = subprocess.Popen(cmd)
        
        # Wait for server to be ready
        if wait_for_server(host, port):
            print()
            print(f"🎉 {service_name.upper()} server is ready!")
            print(f"🔗 Endpoint: http://{host}:{port}/v1/chat/completions")
            print()
            
            # Keep server running
            process.wait()
            
        else:
            print("❌ Server failed to start or become ready")
            process.terminate()
            sys.exit(1)
            
    except KeyboardInterrupt:
        print("\n🛑 Shutting down server...")
        process.terminate()
        process.wait()
        print("✅ Server stopped")
        
    except Exception as e:
        print(f"❌ Error starting server: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
