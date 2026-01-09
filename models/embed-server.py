#!/usr/bin/env python3
"""
Apple Silicon optimized embedding server for Qwen3 models
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
import uvicorn
import torch
from typing import List, Union, Optional
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
port = embed_config.get("port", 8083)
batch_size = embed_config.get("batch_size", 64)
host = server_config.get("host", "127.0.0.1")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global model, model_name

    if not model_name:
        logger.error("❌ Model name not specified in 'config/settings.toml' under [services.embedding].")
        return

    logger.info(f"Loading embedding model: {model_name}")
    logger.info(f"Batch size: {batch_size}")
    
    # Optimize for Apple Silicon
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    logger.info(f"Using device: {device}")
    
    # Load model with trust_remote_code=True for Qwen models
    model = SentenceTransformer(model_name, device=device, trust_remote_code=True)
    
    # Configure max sequence length if needed (Qwen3-Embedding supports up to 32k, but let's stick to reasonable defaults or model defaults)
    # model.max_seq_length = 8192 
    
    logger.info("✅ Qwen3 model loaded successfully")
    
    yield
    
    # Shutdown
    logger.info("Shutting down embedding server")

app = FastAPI(
    title="Qwen3 Embedding Server", 
    version="1.0.0",
    lifespan=lifespan
)

class EmbeddingRequest(BaseModel):
    input: Union[str, List[str]]
    model: str = model_name 
    encoding_format: str = "float" 

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
        
        # Calculate tokens roughly for usage stats (approximation)
        prompt_tokens = sum(len(text.split()) for text in texts) # Very rough approx
        
        # Generate embeddings
        # Batch processing is handled by SentenceTransformer
        embeddings = model.encode(texts, batch_size=batch_size, convert_to_numpy=True, show_progress_bar=False)
        
        # Format response to match OpenAI API
        data = []
        for i, embedding in enumerate(embeddings):
            data.append({
                "object": "embedding",
                "index": i,
                "embedding": embedding.tolist()
            })
        
        return EmbeddingResponse(
            data=data,
            model=model_name,
            usage={
                "prompt_tokens": prompt_tokens,
                "total_tokens": prompt_tokens
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
        "batch_size": batch_size
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
            "dimensions": model.get_sentence_embedding_dimension() if model else 4096
        }]
    }

if __name__ == "__main__":
    if not model_name:
        logger.error("Embedding model name not configured. Exiting.")
    else:
        uvicorn.run(app, host=host, port=port)
