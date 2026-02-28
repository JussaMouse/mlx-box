#!/bin/bash
# Test script to verify thinking tags are being filtered
# Sends a test request and checks for <think> tags in the response

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load API key from config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/settings.toml"

API_KEY=$(grep -A 5 'api_keys = \[' "$CONFIG_FILE" | grep '"' | head -1 | cut -d'"' -f2)
THINKING_PORT=$(python3 - <<'PY'
import tomllib
from pathlib import Path
cfg = tomllib.loads(Path("config/settings.toml").read_text())
services = cfg.get("services", {})
print(services.get("thinking", {}).get("port", 8083))
PY
)
THINKING_MODEL=$(curl -s "http://127.0.0.1:${THINKING_PORT}/v1/models" -H "Authorization: Bearer ${API_KEY}" | jq -r '.data[0].id // "thinking"')

if [ -z "$API_KEY" ]; then
    echo -e "${RED}❌ Could not extract API key from config/settings.toml${NC}"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Testing Thinking Tags Filter (fast/thinking)        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if filter_reasoning or disable_thinking_tags is set in config
FILTER_REASONING=$(grep -A 12 '\[services.thinking\]' "$CONFIG_FILE" | grep -E 'filter_reasoning' | grep -v '^#' | grep 'true' || echo "")
THINKING_DISABLED=$(grep -A 12 '\[services.thinking\]' "$CONFIG_FILE" | grep -E 'disable_thinking_tags' | grep -v '^#' | grep 'true' || echo "")

if [ -z "$FILTER_REASONING" ] && [ -z "$THINKING_DISABLED" ]; then
    echo -e "${YELLOW}⚠ No reasoning filter enabled in config${NC}"
    echo "  Add one of the following under [services.thinking]:"
    echo "    filter_reasoning = true"
    echo "    # or"
    echo "    disable_thinking_tags = true"
    echo ""
    echo "  Then restart the thinking service:"
    echo "    sudo launchctl kickstart -k system/com.mlx-box.thinking"
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ Reasoning filter is enabled in config${NC}"
    echo ""
fi

# Test prompt that should trigger thinking
TEST_PROMPT="Solve this step by step: If x + 5 = 12, what is x? Show your reasoning."

echo -e "${BLUE}Sending test request to thinking service...${NC}"
echo "Prompt: \"$TEST_PROMPT\""
echo ""

# Make request
response=$(curl -s "http://127.0.0.1:${THINKING_PORT}/v1/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"${THINKING_MODEL}\",
        \"messages\": [{\"role\": \"user\", \"content\": \"$TEST_PROMPT\"}],
        \"max_tokens\": 500,
        \"stream\": false
    }")

# Extract content
content=$(echo "$response" | jq -r '.choices[0].message.content // "ERROR"')

if [ "$content" = "ERROR" ]; then
    echo -e "${RED}❌ Request failed${NC}"
    echo "Response: $response"
    exit 1
fi

# Check for thinking tags
if echo "$content" | grep -q '<think>'; then
    echo -e "${RED}❌ FAILED: <think> opening tag found in response${NC}"
    echo ""
    echo "This means disable_thinking_tags is NOT working."
    echo ""
    echo "Response preview:"
    echo "$content" | head -c 500
    echo ""
    echo -e "${YELLOW}Possible causes:${NC}"
    echo "  1. mlx-lm version too old (need >= 0.30.6)"
    echo "  2. Chat template not respecting the parameter"
    echo ""
    echo -e "${YELLOW}Recommended fix:${NC}"
    echo "  Implement streaming filter fallback to post-process responses"
    echo ""
    exit 1
elif echo "$content" | grep -q '</think>'; then
    echo -e "${YELLOW}⚠ PARTIAL: Only </think> closing tag found${NC}"
    echo ""
    echo "This is common - the opening <think> is in the template,"
    echo "but the model still generates the closing tag."
    echo ""
    echo "Response preview:"
    echo "$content" | head -c 500
    echo ""
    echo -e "${YELLOW}Recommendation:${NC}"
    echo "  The parameter is partially working but model ignores it."
    echo "  Need streaming filter fallback to fully remove thinking content."
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ SUCCESS: No thinking tags found in response${NC}"
    echo ""
    echo "The disable_thinking_tags parameter is working correctly!"
    echo ""
    echo "Response:"
    echo "$content"
    echo ""
fi

# Check response quality
tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
echo ""
echo -e "${BLUE}Response stats:${NC}"
echo "  Tokens: $tokens"
echo ""

if [ "$tokens" -lt 20 ]; then
    echo -e "${YELLOW}⚠ Response seems very short. Model may not be functioning properly.${NC}"
else
    echo -e "${GREEN}✓ Response length looks reasonable${NC}"
fi

echo ""
echo -e "${GREEN}Test complete${NC}"
