#!/usr/bin/env python3
"""
Apple Silicon optimized embedding server for Qwen3 models
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
import uvicorn
import torch
from typing import List, Union
from contextlib import asynccontextmanager
import logging
import tomlkit
import sys
from pathlib import Path

# --- Configuration Loading ---
def load_config():
    """Load settings from the TOML config file."""
    try:
        config_path = Path(__file__).parent.parent / "config" / "settings.toml"
        with open(config_path, "r") as f:
            return tomlkit.load(f)
    except FileNotFoundError:
        logging.error("❌ Configuration file 'config/settings.toml' not found.")
        logging.error("   Please copy 'config/settings.toml.example' to 'config/settings.toml' and customize it.")
        sys.exit(1)
    except Exception as e:
        logging.error(f"❌ Error loading configuration: {e}")
        sys.exit(1)

# --- End Configuration Loading ---


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load configuration from settings.toml
config = load_config()
embed_config = config.get("services", {}).get("embedding", {})
server_config = config.get("server", {})

# Global model instance
model = None
model_name = embed_config.get("model")
port = embed_config.get("port", 8081)
host = server_config.get("host", "127.0.0.1")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global model, model_name

    if not model_name:
        logger.error("❌ Model name not specified in 'config/settings.toml' under [services.embedding].")
        # Use sys.exit in a startup event if necessary, or handle gracefully
        return

    logger.info(f"Loading embedding model: {model_name}")
    
    # Optimize for Apple Silicon
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    logger.info(f"Using device: {device}")
    
    model = SentenceTransformer(model_name, device=device)
    logger.info("✅ Qwen3 model loaded successfully")
    
    yield
    
    # Shutdown (cleanup if needed)
    logger.info("Shutting down embedding server")

app = FastAPI(
    title="Qwen3 Embedding Server", 
    version="1.0.0",
    lifespan=lifespan
)

class EmbeddingRequest(BaseModel):
    input: Union[str, List[str]]
    model: str = model_name # Use the loaded model name as default

class EmbeddingResponse(BaseModel):
    object: str = "list"
    data: List[dict]
    model: str
    usage: dict

@app.post("/v1/embeddings")
async def create_embeddings(request: EmbeddingRequest):
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        # Handle both string and list inputs
        texts = [request.input] if isinstance(request.input, str) else request.input
        
        # Generate embeddings with proper instruction handling
        query_embeddings = []
        document_embeddings = []
        
        for text in texts:
            # Simple heuristic: questions get query prompt, others are documents
            if text.strip().endswith('?') or text.lower().startswith(('what', 'how', 'why', 'when', 'where')):
                # Use query prompt for questions
                embedding = model.encode([text], prompt_name="query")[0]
            else:
                # Regular document embedding
                embedding = model.encode([text])[0]
            
            document_embeddings.append(embedding)
        
        # Format response to match OpenAI API
        data = []
        for i, embedding in enumerate(document_embeddings):
            data.append({
                "object": "embedding",
                "index": i,
                "embedding": embedding.tolist()
            })
        
        return EmbeddingResponse(
            data=data,
            model=model_name,
            usage={
                "prompt_tokens": sum(len(text.split()) for text in texts),
                "total_tokens": sum(len(text.split()) for text in texts)
            }
        )
        
    except Exception as e:
        logger.error(f"Error generating embeddings: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    mps_available = torch.backends.mps.is_available() if torch.backends.mps else False
    return {
        "status": "healthy",
        "model": model_name,
        "model_loaded": model is not None,
        "device": "mps" if mps_available else "cpu",
        "apple_silicon_optimized": mps_available
    }

@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [{
            "id": model_name,
            "object": "model",
            "created": 1677610602,
            "owned_by": "qwen",
            "dimensions": 2560  # Qwen3-4B embedding dimensions
        }]
    }

if __name__ == "__main__":
    if not model_name:
        logger.error("Embedding model name not configured. Exiting.")
    else:
        uvicorn.run(app, host=host, port=port)
