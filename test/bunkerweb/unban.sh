#!/bin/bash

cd $(dirname $0)

# Configuration

source .env

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Complex Bot Attack Simulation ===${NC}"

# Dynamic detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Detect port from docker-compose.yml
BUNKERWEB_PORT=$(grep -A 10 "bunkerweb-instance:" "${PROJECT_ROOT}/docker-compose.yml" | grep "ports:" -A 1 | grep -oP '"\K[0-9]+(?=:8080)')
if [ -z "$BUNKERWEB_PORT" ]; then
    echo -e "${RED}FAILURE: Could not detect BunkerWeb port from docker-compose.yml${NC}"
    exit 1
fi
TARGET_URL="http://localhost:${BUNKERWEB_PORT}"

CROWDSEC_ID=$(sudo docker compose -f "${PROJECT_ROOT}/docker-compose.yml" ps -q crowdsec)
BUNKERWEB_ID=$(sudo docker compose -f "${PROJECT_ROOT}/docker-compose.yml" ps -q bunkerweb-instance)

if [ -z "$CROWDSEC_ID" ] || [ -z "$BUNKERWEB_ID" ]; then
    echo -e "${RED}FAILURE: Could not detect CrowdSec or BunkerWeb container.${NC}"
    exit 1
fi

WHITELIST_PATH="/etc/crowdsec/parsers/s02-enrich/whitelists.yaml"

# Function to check if IP is blocked in CrowdSec
is_blocked() {
    sudo docker exec "$CROWDSEC_ID" cscli decisions list --ip "$ATTACKER_IP" | grep -q "$ATTACKER_IP"
}

# --- Environment Prepare ---
echo -e "${YELLOW}[Prepare] Checking for CrowdSec whitelist...${NC}"
HAS_WHITELIST=$(sudo docker exec "$CROWDSEC_ID" ls "$WHITELIST_PATH" 2>/dev/null)

if [ ! -z "$HAS_WHITELIST" ]; then
    echo "Temporarily disabling CrowdSec whitelist to allow bridge IP detection..."
    sudo docker exec "$CROWDSEC_ID" mv "$WHITELIST_PATH" "${WHITELIST_PATH}.bak"
    sudo docker restart "$CROWDSEC_ID" > /dev/null
    echo "CrowdSec restarted. Waiting 10 seconds for initialization..."
    sleep 10
    # Update container ID after restart just in case
    CROWDSEC_ID=$(sudo docker compose -f "${PROJECT_ROOT}/docker-compose.yml" ps -q crowdsec)
fi

# --- Execution ---

# --- Cleanup & Restoration ---
echo -e "\n${BLUE}=== Post-Test Cleanup ===${NC}"

if [ -f "/tmp/crowdsec_whitelist_disabled" ] || [ ! -z "$HAS_WHITELIST" ]; then
    echo "Restoring CrowdSec whitelist..."
    sudo docker exec "$CROWDSEC_ID" mv "${WHITELIST_PATH}.bak" "$WHITELIST_PATH" 2>/dev/null
    sudo docker restart "$CROWDSEC_ID" > /dev/null
    echo "CrowdSec restored. Waiting 10 seconds for bouncer to reconnect..."
    sleep 10
    # Update container ID after restart just in case
    CROWDSEC_ID=$(sudo docker compose -f "${PROJECT_ROOT}/docker-compose.yml" ps -q crowdsec)
fi

echo "Removing decision for ${ATTACKER_IP} in CrowdSec..."
sudo docker exec "$CROWDSEC_ID" cscli decisions delete --ip "${ATTACKER_IP}" > /dev/null

echo "Removing local ban for ${ATTACKER_IP} in BunkerWeb..."
sudo docker exec "$BUNKERWEB_ID" bwcli unban "${ATTACKER_IP}" > /dev/null

echo -e "${GREEN}Cleanup completed.${NC}"
