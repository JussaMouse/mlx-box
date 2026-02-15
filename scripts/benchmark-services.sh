#!/bin/bash
# Benchmark script for MLX services
# Tests throughput, latency, and memory usage across all tiers

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Load API key from config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config/settings.toml"

# Extract first API key from config
API_KEY=$(grep -A 5 'api_keys = \[' "$CONFIG_FILE" | grep '"' | head -1 | cut -d'"' -f2)

if [ -z "$API_KEY" ]; then
    echo -e "${RED}❌ Could not extract API key from config/settings.toml${NC}"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         MLX Service Benchmark - Performance Test          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to benchmark a service
benchmark_service() {
    local name="$1"
    local port="$2"
    local prompt="$3"
    local max_tokens="$4"

    echo -e "${YELLOW}Testing ${name} service (port ${port})...${NC}"

    # Warm-up request (don't measure)
    curl -s "http://127.0.0.1:${port}/v1/models" \
        -H "Authorization: Bearer ${API_KEY}" > /dev/null 2>&1 || {
        echo -e "${RED}  ❌ Service not responding${NC}"
        return 1
    }

    # Actual benchmark request
    local start_time=$(date +%s.%N)

    local response=$(curl -s "http://127.0.0.1:${port}/v1/chat/completions" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"qwen3\",
            \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}],
            \"max_tokens\": ${max_tokens},
            \"stream\": false
        }")

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    # Parse response
    local completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
    local prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
    local total_tokens=$(echo "$response" | jq -r '.usage.total_tokens // 0')

    if [ "$completion_tokens" -eq 0 ]; then
        echo -e "${RED}  ❌ Request failed or returned 0 tokens${NC}"
        echo "  Response: $response" | head -c 200
        return 1
    fi

    # Calculate tokens per second
    local tokens_per_sec=$(echo "scale=2; $completion_tokens / $duration" | bc)
    local duration_formatted=$(printf "%.2f" "$duration")

    echo -e "${GREEN}  ✓ Success${NC}"
    echo "  Duration: ${duration_formatted}s"
    echo "  Tokens: ${completion_tokens} generated, ${prompt_tokens} prompt, ${total_tokens} total"
    echo "  Speed: ${tokens_per_sec} tokens/sec"
    echo ""

    # Store results for summary
    echo "${name},${duration_formatted},${completion_tokens},${tokens_per_sec}" >> /tmp/mlx_benchmark_results.txt
}

# Initialize results file
rm -f /tmp/mlx_benchmark_results.txt
echo "service,duration,tokens,tok_per_sec" > /tmp/mlx_benchmark_results.txt

# Benchmark each service
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}1. Router Service (Classification)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
benchmark_service "Router" 8082 "Classify this request: What is 2+2?" 50

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}2. Fast Service (General Chat)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
benchmark_service "Fast" 8080 "Write a 200 word paragraph about artificial intelligence." 300

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}3. Thinking Service (Reasoning)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
benchmark_service "Thinking" 8081 "Solve this step by step: If a train travels 120 km in 2 hours, what is its average speed?" 500

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}4. Embedding Service${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

echo -e "${YELLOW}Testing Embedding service (port 8083)...${NC}"
start_time=$(date +%s.%N)

embed_response=$(curl -s "http://127.0.0.1:8083/v1/embeddings" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "input": "This is a test document for semantic embedding.",
        "prefix": "passage"
    }')

end_time=$(date +%s.%N)
embed_duration=$(echo "$end_time - $start_time" | bc)
embed_duration_formatted=$(printf "%.3f" "$embed_duration")

embed_dims=$(echo "$embed_response" | jq -r '.data[0].embedding | length')

if [ "$embed_dims" -gt 0 ]; then
    echo -e "${GREEN}  ✓ Success${NC}"
    echo "  Duration: ${embed_duration_formatted}s"
    echo "  Dimensions: ${embed_dims}"
    echo ""
else
    echo -e "${RED}  ❌ Request failed${NC}"
    echo "  Response: $embed_response" | head -c 200
    echo ""
fi

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    SUMMARY                                ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Display results table
printf "%-12s %-12s %-15s %-15s\n" "Service" "Duration" "Tokens" "Tokens/sec"
printf "%-12s %-12s %-15s %-15s\n" "--------" "--------" "------" "----------"

tail -n +2 /tmp/mlx_benchmark_results.txt | while IFS=, read -r service duration tokens tok_per_sec; do
    printf "%-12s %-12s %-15s %-15s\n" "$service" "${duration}s" "$tokens" "$tok_per_sec"
done

echo ""
echo -e "${GREEN}✓ Benchmark complete${NC}"
echo ""

# Memory check
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                 Memory Usage                              ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

# Get total Python MLX process memory
total_mem=$(ps aux | grep -E 'python.*mlx|python.*embed|python.*ocr' | grep -v grep | awk '{sum+=$6} END {printf "%.2f", sum/1024/1024}')
echo "MLX Services: ${total_mem} GB"

# Check swap
swap_used=$(sysctl vm.swapusage | grep -oE 'used = [0-9.]+[A-Z]' | awk '{print $3}')
echo "Swap Used: ${swap_used}"

if [[ "$swap_used" =~ ^[0-9.]+M$ ]] && (( $(echo "$swap_used" | sed 's/M//') < 100 )); then
    echo -e "${GREEN}✓ Swap usage is healthy${NC}"
elif [[ "$swap_used" =~ ^[0-9.]+G$ ]]; then
    echo -e "${RED}⚠ Warning: Significant swap usage detected (${swap_used})${NC}"
    echo "  Consider reducing max_tokens or concurrent requests"
else
    echo -e "${GREEN}✓ Swap usage is healthy${NC}"
fi

echo ""
echo "Full report saved to: /tmp/mlx_benchmark_results.txt"
