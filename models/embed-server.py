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

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global model instance
model = None
model_name = "Qwen/Qwen3-Embedding-4B"

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global model, model_name
    logger.info(f"Loading Qwen3 model: {model_name}")
    
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
    model: str = "Qwen/Qwen3-Embedding-4B"

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
    uvicorn.run(app, host="127.0.0.1", port=8081)
