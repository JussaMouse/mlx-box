#!/usr/bin/env python3
"""
Interactive Command-Line Chat for MLX Server
"""

import requests
import json
import sys
from pathlib import Path
import tomllib

def load_config():
    config_path = Path(__file__).parent.parent / "config" / "settings.toml"
    try:
        return tomllib.loads(config_path.read_text())
    except Exception:
        return {}


config = load_config()
services = config.get("services", {})
server = config.get("server", {})

HOST = server.get("host", "127.0.0.1")
PORT = services.get("fast", {}).get("port", 8081)
SERVER_URL = f"http://{HOST}:{PORT}/v1"

def get_model_name():
    """
    Fetches an appropriate chat model from the server.
    Prefers a model with 'instruct' in the name.
    """
    try:
        response = requests.get(f"{SERVER_URL}/models", timeout=10)
        response.raise_for_status()
        data = response.json()
        models = data.get("data", [])
        
        if not models:
            return None

        # Look for a chat-tuned model first
        for model in models:
            if "instruct" in model.get("id", "").lower():
                print(f"✅ Found instruction-tuned model: {model['id']}")
                return model["id"]
        
        # If no instruct model, fall back to the first one but warn the user
        fallback_model = models[0].get("id")
        if fallback_model:
            print(f"⚠️ Could not find an 'instruct' model. Falling back to the first available: {fallback_model}", file=sys.stderr)
            return fallback_model
        
        return None

    except requests.exceptions.RequestException as e:
        print(f"❌ Error connecting to server: {e}", file=sys.stderr)
        return None

def interactive_chat(model_name):
    """Main function to run the interactive chat loop."""
    messages = []
    print("=====================================================")
    print(f"  Interactive Chat with: {model_name}")
    print("=====================================================")
    print("Type 'exit' or 'quit' to end the conversation.")
    print()

    while True:
        try:
            user_input = input("You: ")
            if user_input.lower() in ["exit", "quit"]:
                print("\n👋 Goodbye!")
                break

            messages.append({"role": "user", "content": user_input})

            print("Bot: ", end="", flush=True)
            
            # Prepare request data
            request_data = {
                "model": model_name,
                "messages": messages,
                "stream": True,
                "max_tokens": 2048,
            }

            # Send request and handle streaming response
            full_response = ""
            with requests.post(f"{SERVER_URL}/chat/completions", json=request_data, stream=True) as response:
                response.raise_for_status()
                for chunk in response.iter_lines():
                    if chunk:
                        decoded_chunk = chunk.decode('utf-8')
                        if decoded_chunk.startswith('data: '):
                            json_str = decoded_chunk[6:]
                            if json_str.strip() == '[DONE]':
                                break
                            try:
                                data = json.loads(json_str)
                                delta = data["choices"][0].get("delta", {}).get("content", "")
                                if delta:
                                    print(delta, end="", flush=True)
                                    full_response += delta
                            except json.JSONDecodeError:
                                # Ignore malformed data chunks
                                pass
            
            print() # Newline after bot finishes
            if full_response:
                messages.append({"role": "assistant", "content": full_response})

        except requests.exceptions.RequestException as e:
            print(f"\n❌ Error during chat: {e}", file=sys.stderr)
            break
        except KeyboardInterrupt:
            print("\n\n👋 Goodbye!")
            break
        except Exception as e:
            print(f"\nAn unexpected error occurred: {e}", file=sys.stderr)
            break

if __name__ == "__main__":
    print("🔎 Finding running model...")
    model = get_model_name()
    if model:
        interactive_chat(model)
    else:
        print(f"❌ Could not get model from server.", file=sys.stderr)
        print(f"   Please ensure the MLX server is running at {SERVER_URL}", file=sys.stderr)
        sys.exit(1) 
