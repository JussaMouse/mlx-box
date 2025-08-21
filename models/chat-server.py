#!/usr/bin/env python3
"""
MLX Chat Server for Qwen2.5-72B-Instruct
OpenAI-compatible API for Wooster integration
"""

import subprocess
import sys
import os
import time
import requests
from pathlib import Path

def check_mlx_available():
    """Check if MLX is available on this system"""
    try:
        import mlx
        import mlx_lm
        return True
    except ImportError:
        return False

def wait_for_server(host="127.0.0.1", port=8080, timeout=60):
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

def test_server(host="127.0.0.1", port=8080):
    """Test the server with a simple chat completion"""
    try:
        response = requests.post(
            f"http://{host}:{port}/v1/chat/completions",
            json={
                "model": "qwen2.5-72b-instruct",
                "messages": [{"role": "user", "content": "Hello! Can you confirm you're working?"}],
                "max_tokens": 50,
                "temperature": 0.7
            },
            timeout=30
        )
        
        if response.status_code == 200:
            data = response.json()
            content = data["choices"][0]["message"]["content"]
            print(f"✅ Server test successful!")
            print(f"Response: {content}")
            return True
        else:
            print(f"❌ Server test failed: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ Server test error: {e}")
        return False

def main():
    """Main function to start the MLX chat server"""
    
    # Check if MLX is available
    if not check_mlx_available():
        print("❌ MLX not available. Install with: poetry add mlx mlx-lm")
        sys.exit(1)
    
    # Configuration
    model_options = {
        "4bit": "mlx-community/Qwen2.5-72B-Instruct-4bit",      # ~40GB RAM
        "8bit": "mlx-community/Qwen2.5-72B-Instruct-8bit",      # ~80GB RAM  
        "6bit": "mlx-community/Qwen2.5-72B-Instruct-6bit",      # ~60GB RAM
    }
    
    # Default to 4bit for most systems
    model_name = model_options["4bit"]
    port = 8080
    host = "0.0.0.0"
    
    # Allow model selection via command line
    if len(sys.argv) > 1:
        quant = sys.argv[1].lower()
        if quant in model_options:
            model_name = model_options[quant]
            print(f"Using {quant} quantization: {model_name}")
        else:
            print(f"Available quantizations: {list(model_options.keys())}")
            sys.exit(1)
    
    print(f"🚀 Starting MLX server with {model_name}")
    print(f"📍 Server will be available at: http://{host}:{port}")
    print(f"🔄 This will download the model on first run (~20-40GB)")
    print(f"⏱️  Model loading may take 2-5 minutes...")
    print()
    
    # Start the MLX server
    try:
        cmd = [
            sys.executable, "-m", "mlx_lm", "server",
            "--model", model_name,
            "--port", str(port),
            "--host", host,
            "--max-tokens", "4096"
        ]
        
        print(f"Running: {' '.join(cmd)}")
        print("=" * 50)
        
        # Start server process
        process = subprocess.Popen(cmd)
        
        # Wait for server to be ready
        if wait_for_server(host, port):
            # Test the server
            test_server(host, port)
            
            print()
            print("🎉 Qwen2.5-72B server is ready for Wooster!")
            print()
            print("📋 Wooster Configuration:")
            print("Add this to your Wooster config:")
            print(f"""
{{
  "routing": {{
    "providers": {{
      "local": {{
        "chat": {{
          "enabled": true,
          "baseURL": "http://{host}:{port}/v1",
          "model": "qwen2.5-72b-instruct",
          "supportsStreaming": true
        }}
      }}
    }}
  }}
}}
            """)
            
            print("\n🔗 Test endpoints:")
            print(f"• Models: http://{host}:{port}/v1/models")
            print(f"• Chat: http://{host}:{port}/v1/chat/completions")
            print(f"• Health: http://{host}:{port}/health")
            
            print("\n⏹️  Press Ctrl+C to stop the server")
            
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
