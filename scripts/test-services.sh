#!/bin/bash
# Test all MLX-Box services after optimization
# Uses ports from config/settings.toml and defaults to localhost.

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load config
CONFIG_FILE="$(dirname "$0")/config/settings.toml"

# Validate config before running tests
if [ -f "scripts/validate-config.py" ]; then
    python3 scripts/validate-config.py || exit 1
fi

# Extract domain, API key, and ports from config (or use defaults)
if [ -f "$CONFIG_FILE" ]; then
    read -r DOMAIN API_KEY ROUTER_PORT FAST_PORT THINKING_PORT EMBEDDING_PORT OCR_PORT TTS_PORT WHISPER_PORT TTS_VOICE < <(
        python3 - <<'PY'
import tomllib
from pathlib import Path

cfg = tomllib.loads(Path("config/settings.toml").read_text())
server = cfg.get("server", {})
services = cfg.get("services", {})

domain = server.get("domain_name", "localhost")
api_keys = server.get("api_keys", [])
api_key = api_keys[0] if api_keys else "test-key"

def port(name, default):
    return services.get(name, {}).get("port", default)

tts_voice = services.get("tts", {}).get("default_voice", "")

print(
    domain,
    api_key,
    port("router", 8080),
    port("fast", 8081),
    port("thinking", 8083),
    port("embedding", 8084),
    port("ocr", 8085),
    port("tts", 8086),
    port("whisper", 8087),
    tts_voice,
)
PY
    )
else
    echo "Config file not found, using localhost"
    DOMAIN="localhost"
    API_KEY="test-key"
    ROUTER_PORT=8080
    FAST_PORT=8081
    THINKING_PORT=8083
    EMBEDDING_PORT=8084
    OCR_PORT=8085
    TTS_PORT=8086
    WHISPER_PORT=8087
    TTS_VOICE=""
fi

# Default to localhost for direct service testing (override with TEST_BASE_URL)
TEST_BASE_URL="${TEST_BASE_URL:-http://127.0.0.1}"

# Helper: fetch model id from /v1/models (fallback to service name)
get_model_id() {
    local port="$1"
    local fallback="$2"
    local response
    response=$(curl -s "${TEST_BASE_URL}:${port}/v1/models" -H "Authorization: Bearer $API_KEY")
    local model
    model=$(echo "$response" | jq -r '.data[0].id // empty' 2>/dev/null)
    if [ -n "$model" ] && [ "$model" != "null" ]; then
        echo "$model"
    else
        echo "$fallback"
    fi
}

ROUTER_MODEL=$(get_model_id "$ROUTER_PORT" "router")
FAST_MODEL=$(get_model_id "$FAST_PORT" "fast")
THINKING_MODEL=$(get_model_id "$THINKING_PORT" "thinking")
EMBEDDING_MODEL=$(get_model_id "$EMBEDDING_PORT" "embedding")
TTS_MODEL=$(get_model_id "$TTS_PORT" "tts")
WHISPER_MODEL=$(get_model_id "$WHISPER_PORT" "small.en")

echo -e "${BLUE}=== Testing MLX-Box Services ===${NC}"
echo "Domain: $DOMAIN"
echo "Base URL: $TEST_BASE_URL"
echo "Ports: router=$ROUTER_PORT fast=$FAST_PORT thinking=$THINKING_PORT embedding=$EMBEDDING_PORT ocr=$OCR_PORT tts=$TTS_PORT whisper=$WHISPER_PORT"
echo ""

# Test 1: Router Service - Should be deterministic with temp=0.1
echo -e "${BLUE}[1/7] Testing Router Service (Port ${ROUTER_PORT})${NC}"
echo "Expected: Deterministic classification, same answer every time"
echo ""

for i in 1 2; do
    echo "Attempt $i:"
    RESPONSE=$(curl -s -X POST "${TEST_BASE_URL}:${ROUTER_PORT}/v1/chat/completions" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$ROUTER_MODEL"'",
            "messages": [{"role": "user", "content": "What is 2+2?"}],
            "max_tokens": 20
        }')

    if [ $? -eq 0 ]; then
        CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)
        if [ "$CONTENT" != "null" ] && [ -n "$CONTENT" ]; then
            echo -e "${GREEN}✓${NC} Response: $CONTENT"
        else
            echo -e "${RED}✗${NC} Invalid response"
            echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
        fi
    else
        echo -e "${RED}✗${NC} Connection failed"
    fi
    echo ""
done

# Test 2: Fast Service - Should handle longer context (8192)
echo -e "${BLUE}[2/7] Testing Fast Service (Port ${FAST_PORT})${NC}"
echo "Expected: Handles 8192 token context, temp=0.6 for balanced responses"
echo ""

RESPONSE=$(curl -s -X POST "${TEST_BASE_URL}:${FAST_PORT}/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$FAST_MODEL"'",
        "messages": [{"role": "user", "content": "Write a haiku about AI"}],
        "max_tokens": 100
    }')

if [ $? -eq 0 ]; then
    CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)
    USAGE=$(echo "$RESPONSE" | jq '.usage' 2>/dev/null)

    if [ "$CONTENT" != "null" ] && [ -n "$CONTENT" ]; then
        echo -e "${GREEN}✓${NC} Response received"
        echo "Content: $CONTENT"
        echo "Token usage: $USAGE"
    else
        echo -e "${RED}✗${NC} Invalid response"
        echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    fi
else
    echo -e "${RED}✗${NC} Connection failed"
fi
echo ""

# Test 3: Thinking Service - Should handle complex reasoning
echo -e "${BLUE}[3/7] Testing Thinking Service (Port ${THINKING_PORT})${NC}"
echo "Expected: Handles 16384 token context, temp=0.2 for precise reasoning"
echo ""

RESPONSE=$(curl -s -X POST "${TEST_BASE_URL}:${THINKING_PORT}/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$THINKING_MODEL"'",
        "messages": [{"role": "user", "content": "Explain binary search in one sentence"}],
        "max_tokens": 200
    }')

if [ $? -eq 0 ]; then
    CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)
    USAGE=$(echo "$RESPONSE" | jq '.usage' 2>/dev/null)

    if [ "$CONTENT" != "null" ] && [ -n "$CONTENT" ]; then
        echo -e "${GREEN}✓${NC} Response received"
        echo "Content: $CONTENT"
        echo "Token usage: $USAGE"
    else
        echo -e "${RED}✗${NC} Invalid response"
        echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    fi
else
    echo -e "${RED}✗${NC} Connection failed"
fi
echo ""

# Test 4: Embedding Service
echo -e "${BLUE}[4/7] Testing Embedding Service (Port ${EMBEDDING_PORT})${NC}"
echo "Expected: Returns embedding vector"
echo ""

RESPONSE=$(curl -s -X POST "${TEST_BASE_URL}:${EMBEDDING_PORT}/v1/embeddings" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$EMBEDDING_MODEL"'",
        "input": "Hello world"
    }')

if [ $? -eq 0 ]; then
    EMBEDDING_DIM=$(echo "$RESPONSE" | jq '.data[0].embedding | length' 2>/dev/null)

    if [ "$EMBEDDING_DIM" != "null" ] && [ "$EMBEDDING_DIM" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Embedding generated"
        echo "Dimensions: $EMBEDDING_DIM"
    else
        echo -e "${RED}✗${NC} Invalid response"
        echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    fi
else
    echo -e "${RED}✗${NC} Connection failed"
fi
echo ""

# Test 5: OCR Service - Would need an image, so just check if it's running
echo -e "${BLUE}[5/7] Testing OCR Service (Port ${OCR_PORT})${NC}"
echo "Expected: Service is running (image test would require actual image)"
echo ""

RESPONSE=$(curl -s "${TEST_BASE_URL}:${OCR_PORT}/v1/models" \
    -H "Authorization: Bearer $API_KEY")

if [ $? -eq 0 ]; then
    MODEL=$(echo "$RESPONSE" | jq -r '.data[0].id' 2>/dev/null)

    if [ "$MODEL" != "null" ] && [ -n "$MODEL" ]; then
        echo -e "${GREEN}✓${NC} OCR service is running"
        echo "Model: $MODEL"
    else
        echo -e "${RED}✗${NC} Invalid response"
        echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    fi
else
    echo -e "${RED}✗${NC} Connection failed"
fi
echo ""

# Test 6: TTS Service - Generate a short clip
echo -e "${BLUE}[6/7] Testing TTS Service (Port ${TTS_PORT})${NC}"
echo "Expected: Returns audio bytes"
echo ""

TTS_OUT="/tmp/mlx_box_tts_test.wav"
HTTP_CODE=$(curl -s -o "$TTS_OUT" -w "%{http_code}" -X POST "${TEST_BASE_URL}:${TTS_PORT}/v1/audio/speech" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"$TTS_MODEL"'",
        "input": "Hello from MLX-Box TTS.",
        "voice": "'"$TTS_VOICE"'"
    }')

if [ "$HTTP_CODE" -eq 200 ] && [ -s "$TTS_OUT" ]; then
    SIZE=$(wc -c < "$TTS_OUT" | tr -d ' ')
    echo -e "${GREEN}✓${NC} TTS audio generated (${SIZE} bytes)"
else
    echo -e "${RED}✗${NC} TTS request failed (HTTP ${HTTP_CODE})"
    [ -f "$TTS_OUT" ] && head -c 200 "$TTS_OUT"
fi
echo ""

# Test 7: Whisper Service - Transcribe a synthetic audio clip
echo -e "${BLUE}[7/7] Testing Whisper Service (Port ${WHISPER_PORT})${NC}"
echo "Expected: Returns transcription JSON"
echo ""

WHISPER_WAV="/tmp/mlx_box_whisper_test.wav"
python3 - <<'PY'
import math
import wave
import struct

sample_rate = 16000
duration_sec = 1.0
freq = 440.0

num_samples = int(sample_rate * duration_sec)
with wave.open("/tmp/mlx_box_whisper_test.wav", "w") as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(sample_rate)
    for i in range(num_samples):
        val = int(32767.0 * math.sin(2 * math.pi * freq * (i / sample_rate)))
        wf.writeframes(struct.pack("<h", val))
PY

RESPONSE=$(curl -s -X POST "${TEST_BASE_URL}:${WHISPER_PORT}/v1/audio/transcriptions" \
    -H "Authorization: Bearer $API_KEY" \
    -F "file=@${WHISPER_WAV}" \
    -F "model=${WHISPER_MODEL}")

if [ $? -eq 0 ]; then
    TEXT=$(echo "$RESPONSE" | jq -r '.text' 2>/dev/null)
    if [ "$TEXT" != "null" ]; then
        echo -e "${GREEN}✓${NC} Whisper response received"
        echo "Text: ${TEXT}"
    else
        echo -e "${YELLOW}⚠${NC} Whisper response missing text"
        echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    fi
else
    echo -e "${RED}✗${NC} Connection failed"
fi
echo ""

# Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo ""
echo "Router (${ROUTER_PORT}):    Deterministic classification with temp=0.1"
echo "Fast (${FAST_PORT}):      Balanced responses with temp=0.6, 8192 context"
echo "Thinking (${THINKING_PORT}):  Precise reasoning with temp=0.2, 16384 context"
echo "Embedding (${EMBEDDING_PORT}): Vector embeddings for semantic search"
echo "OCR (${OCR_PORT}):       Vision model for text extraction"
echo "TTS (${TTS_PORT}):       Text-to-speech synthesis"
echo "Whisper (${WHISPER_PORT}): Speech-to-text transcription"
echo ""
echo "Next: Test new system prompts by asking Bartleby a question!"
