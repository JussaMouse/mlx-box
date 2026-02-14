#!/bin/bash
# Test all MLX-Box services after optimization
# Tests: Router (8082), Fast (8080), Thinking (8081), Embedding (8083), OCR (8085)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load config
CONFIG_FILE="$(dirname "$0")/config/settings.toml"

# Extract domain from config (or use localhost)
if [ -f "$CONFIG_FILE" ]; then
    DOMAIN=$(grep "domain_name" "$CONFIG_FILE" | cut -d'"' -f2)
    # Get first API key
    API_KEY=$(grep -A5 "api_keys" "$CONFIG_FILE" | grep '"' | head -1 | cut -d'"' -f2)
else
    echo "Config file not found, using localhost"
    DOMAIN="localhost"
    API_KEY="test-key"
fi

# Use https for domain, http for localhost
if [ "$DOMAIN" = "localhost" ]; then
    BASE_URL="http://localhost"
else
    BASE_URL="https://$DOMAIN"
fi

echo -e "${BLUE}=== Testing MLX-Box Services ===${NC}"
echo "Domain: $DOMAIN"
echo "Base URL: $BASE_URL"
echo ""

# Test 1: Router Service (8082) - Should be deterministic with temp=0.1
echo -e "${BLUE}[1/5] Testing Router Service (Port 8082)${NC}"
echo "Expected: Deterministic classification, same answer every time"
echo ""

for i in 1 2; do
    echo "Attempt $i:"
    RESPONSE=$(curl -s -X POST "${BASE_URL}:8082/v1/chat/completions" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "router",
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

# Test 2: Fast Service (8080) - Should handle longer context (8192)
echo -e "${BLUE}[2/5] Testing Fast Service (Port 8080)${NC}"
echo "Expected: Handles 8192 token context, temp=0.6 for balanced responses"
echo ""

RESPONSE=$(curl -s -X POST "${BASE_URL}:8080/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "fast",
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

# Test 3: Thinking Service (8081) - Should handle complex reasoning
echo -e "${BLUE}[3/5] Testing Thinking Service (Port 8081)${NC}"
echo "Expected: Handles 16384 token context, temp=0.2 for precise reasoning"
echo ""

RESPONSE=$(curl -s -X POST "${BASE_URL}:8081/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "thinking",
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

# Test 4: Embedding Service (8083)
echo -e "${BLUE}[4/5] Testing Embedding Service (Port 8083)${NC}"
echo "Expected: Returns embedding vector"
echo ""

RESPONSE=$(curl -s -X POST "${BASE_URL}:8083/v1/embeddings" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "embedding",
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

# Test 5: OCR Service (8085) - Would need an image, so just check if it's running
echo -e "${BLUE}[5/5] Testing OCR Service (Port 8085)${NC}"
echo "Expected: Service is running (image test would require actual image)"
echo ""

RESPONSE=$(curl -s "${BASE_URL}:8085/v1/models" \
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

# Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo ""
echo "Router (8082):    Deterministic classification with temp=0.1"
echo "Fast (8080):      Balanced responses with temp=0.6, 8192 context"
echo "Thinking (8081):  Precise reasoning with temp=0.2, 16384 context"
echo "Embedding (8083): Vector embeddings for semantic search"
echo "OCR (8085):       Vision model for text extraction"
echo ""
echo "Next: Test new system prompts by asking Bartleby a question!"
