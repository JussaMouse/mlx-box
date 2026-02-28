#!/bin/bash
# Restart all MLX-Box services
# This restarts both backend MLX servers and auth proxies

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Restarting All MLX-Box Services                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# List of all services (backend + auth proxy pairs)
SERVICES=(
    "com.mlx-box.router-backend"
    "com.mlx-box.router"
    "com.mlx-box.fast-backend"
    "com.mlx-box.fast"
    "com.mlx-box.thinking-backend"
    "com.mlx-box.thinking"
    "com.mlx-box.embedding-backend"
    "com.mlx-box.embedding"
    "com.mlx-box.ocr-backend"
    "com.mlx-box.ocr"
    "com.mlx-box.tts-backend"
    "com.mlx-box.tts"
    "com.mlx-box.whisper-backend"
    "com.mlx-box.whisper"
)

echo -e "${YELLOW}Restarting ${#SERVICES[@]} services...${NC}"
echo ""

# Counter for successful restarts
SUCCESS=0
FAILED=0

# Restart each service
for service in "${SERVICES[@]}"; do
    printf "Restarting %-35s ... " "$service"

    if sudo launchctl kickstart -k system/"$service" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((SUCCESS++))
    else
        echo -e "${YELLOW}⚠ (may not be loaded)${NC}"
        ((FAILED++))
    fi
done

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Successfully restarted: $SUCCESS${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warnings: $FAILED (services may not be installed)${NC}"
fi
echo ""

# Give services a moment to start
echo "Waiting 3 seconds for services to initialize..."
sleep 3

echo ""
echo -e "${BLUE}Service Status:${NC}"
sudo launchctl list | grep -E "mlx-box|mlx" | grep -v grep | awk '{printf "  %-40s PID: %-8s Status: %s\n", $3, $1, $2}'

echo ""
echo -e "${GREEN}✓ All services restarted${NC}"
echo ""
echo "Check logs if any service failed to start:"
echo "  tail -f ~/Library/Logs/com.mlx-box.*/stderr.log"
