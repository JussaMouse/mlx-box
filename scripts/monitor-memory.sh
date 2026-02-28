#!/bin/bash
# Memory monitoring script for MLX services
# Displays real-time memory usage, warnings for pressure, and recommendations

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║               MLX Service Memory Monitor                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to format bytes to GB
format_gb() {
    local bytes=$1
    echo "scale=2; $bytes / 1024 / 1024 / 1024" | bc
}

# Function to get memory in MB for a process pattern
get_process_memory_mb() {
    local pattern=$1
    ps aux | grep "$pattern" | grep -v grep | awk '{sum+=$6} END {printf "%.0f", sum/1024}'
}

# Get system memory info
get_memory_stats() {
    # Total memory (in bytes, convert to GB)
    local total_mem=$(sysctl -n hw.memsize)
    local total_gb=$(format_gb "$total_mem")

    # Memory pressure
    local mem_pressure=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print $5}' | tr -d '%')

    # Swap usage
    local swap_info=$(sysctl vm.swapusage | grep -oE '[0-9.]+[MG]' | head -3)
    local swap_total=$(echo "$swap_info" | sed -n 1p)
    local swap_used=$(echo "$swap_info" | sed -n 2p)
    local swap_free=$(echo "$swap_info" | sed -n 3p)

    # Get individual service memory
    local router_mem=$(get_process_memory_mb "chat-server.py.*router")
    local fast_mem=$(get_process_memory_mb "chat-server.py.*fast")
    local thinking_mem=$(get_process_memory_mb "chat-server.py.*thinking")
    local embed_mem=$(get_process_memory_mb "embed-server.py")
    local ocr_mem=$(get_process_memory_mb "ocr-server.py")
    local tts_mem=$(get_process_memory_mb "voice/tts-server.py")
    local whisper_mem=$(get_process_memory_mb "voice/whisper-server.py")

    # Calculate total MLX memory
    local total_mlx_mem=$((router_mem + fast_mem + thinking_mem + embed_mem + ocr_mem + tts_mem + whisper_mem))
    local total_mlx_gb=$(echo "scale=2; $total_mlx_mem / 1024" | bc)

    # Calculate used memory (approximation based on free)
    local free_percentage=${mem_pressure:-0}
    local used_gb=$(echo "scale=2; $total_gb * (100 - $free_percentage) / 100" | bc)
    local free_gb=$(echo "scale=2; $total_gb * $free_percentage / 100" | bc)

    echo -e "${BLUE}System Memory (total: ${total_gb} GB):${NC}"
    printf "  Total:    %.2f GB\n" "$total_gb"
    printf "  Used:     %.2f GB (%.0f%%)\n" "$used_gb" "$(echo "100 - $free_percentage" | bc)"
    printf "  Free:     %.2f GB (%.0f%%)\n" "$free_gb" "$free_percentage"
    echo ""

    echo -e "${BLUE}MLX Services Memory:${NC}"
    printf "  Router:    %4d MB (Qwen3-0.6B-4bit)\n" "$router_mem"
    printf "  Fast:      %4d MB (Qwen3.5-35B-A3B-4bit)\n" "$fast_mem"
    printf "  Thinking:  %4d MB (Qwen3.5-122B-A10B mxfp4)\n" "$thinking_mem"
    printf "  Embedding: %4d MB (Qwen3-Embedding-8B)\n" "$embed_mem"
    printf "  OCR:       %4d MB (olmOCR-2-7B-8bit)\n" "$ocr_mem"
    printf "  TTS:       %4d MB (Qwen3-TTS)\n" "$tts_mem"
    printf "  Whisper:   %4d MB (Whisper STT)\n" "$whisper_mem"
    echo "  ─────────────────"
    printf "  Total:     %.2f GB\n" "$total_mlx_gb"
    echo ""

    # Calculate headroom
    local headroom=$(echo "$total_gb - $used_gb" | bc)

    echo -e "${BLUE}Memory Analysis:${NC}"
    printf "  Headroom:  %.2f GB available for KV cache\n" "$headroom"
    echo ""

    echo -e "${BLUE}Swap Usage:${NC}"
    echo "  Total:     $swap_total"
    echo "  Used:      $swap_used"
    echo "  Free:      $swap_free"
    echo ""

    # Health assessment
    echo -e "${BLUE}Health Status:${NC}"

    # Check free memory
    if (( $(echo "$free_percentage < 10" | bc -l) )); then
        echo -e "  ${RED}⚠ CRITICAL: Very low free memory (<10%)${NC}"
        echo "    → Reduce max_tokens or concurrent requests"
    elif (( $(echo "$free_percentage < 20" | bc -l) )); then
        echo -e "  ${YELLOW}⚠ WARNING: Low free memory (<20%)${NC}"
        echo "    → Monitor closely, consider reducing load"
    else
        echo -e "  ${GREEN}✓ Memory pressure: Healthy${NC}"
    fi

    # Check swap
    if [[ "$swap_used" =~ ^0 ]]; then
        echo -e "  ${GREEN}✓ Swap usage: None (optimal)${NC}"
    elif [[ "$swap_used" =~ M$ ]] && (( $(echo "$swap_used" | sed 's/M//') < 100 )); then
        echo -e "  ${GREEN}✓ Swap usage: Minimal (<100MB)${NC}"
    elif [[ "$swap_used" =~ M$ ]]; then
        echo -e "  ${YELLOW}⚠ Swap usage: $(echo $swap_used) (minor concern)${NC}"
    else
        echo -e "  ${RED}⚠ CRITICAL: Heavy swap usage (${swap_used})${NC}"
        echo "    → System is memory-constrained, performance degraded"
        echo "    → Reduce max_tokens or restart services"
    fi

    # Estimate concurrent request capacity
    echo ""
    echo -e "${BLUE}Estimated Capacity (based on current headroom):${NC}"

    # Assume 4GB per fast request, 8GB per thinking request
    local fast_capacity=$(echo "$headroom / 4" | bc)
    local thinking_capacity=$(echo "$headroom / 8" | bc)

    printf "  Fast (8K-16K context):     ~%d concurrent requests\n" "$fast_capacity"
    printf "  Thinking (16K-32K context): ~%d concurrent requests\n" "$thinking_capacity"
    echo ""

    # Recommendations
    echo -e "${BLUE}Optimization Recommendations:${NC}"

    if (( $(echo "$total_mlx_gb < 60" | bc -l) )); then
        echo -e "  ${YELLOW}⚠ MLX services using less than expected (<60GB)${NC}"
        echo "    → Models may not be fully loaded"
        echo "    → Check logs: tail -f ~/Library/Logs/com.mlx-box.*/stderr.log"
    elif (( $(echo "$total_mlx_gb > 80" | bc -l) )); then
        echo -e "  ${YELLOW}⚠ MLX services using more than expected (>80GB)${NC}"
        echo "    → Large KV cache from concurrent/long requests"
        echo "    → This is normal under load"
    else
        echo -e "  ${GREEN}✓ Memory usage is within expected range (60-80GB)${NC}"
    fi

    if (( $(echo "$headroom > 50" | bc -l) )); then
        echo -e "  ${GREEN}✓ Excellent headroom (>50GB) - can increase max_tokens${NC}"
        echo "    → Safe to use 32K context on thinking service"
    elif (( $(echo "$headroom > 30" | bc -l) )); then
        echo -e "  ${GREEN}✓ Good headroom (>30GB) - current config is optimal${NC}"
    elif (( $(echo "$headroom > 15" | bc -l) )); then
        echo -e "  ${YELLOW}⚠ Moderate headroom (15-30GB) - consider reducing max_tokens${NC}"
    else
        echo -e "  ${RED}⚠ Low headroom (<15GB) - reduce max_tokens immediately${NC}"
    fi
}

# Main execution
get_memory_stats

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo "Run this script periodically or use 'watch' for continuous monitoring:"
echo "  watch -n 5 $0"
echo ""
