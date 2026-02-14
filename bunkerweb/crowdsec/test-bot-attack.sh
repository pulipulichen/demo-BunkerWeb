#!/bin/bash

# Configuration
TARGET_URL="http://localhost:8080"
ATTACKER_IP="10.20.30.1"

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

# 1. Test Normal Request
echo -e "${YELLOW}[1/4] Sending normal request from ${ATTACKER_IP}...${NC}"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET_URL}/")
if [ "$STATUS" -eq "200" ]; then
    echo -e "${GREEN}SUCCESS: Initial request returned 200 OK.${NC}"
else
    echo -e "${RED}FAILURE: Initial request returned ${STATUS}.${NC}"
    # Continue anyway, might be already blocked
fi

# 2. Trigger Bad User-Agent
echo -e "${YELLOW}[2/4] Triggering 'http-bad-user-agent' (UA: sqlmap/1.8)...${NC}"
curl -s -A "sqlmap/1.8" -o /dev/null "${TARGET_URL}/"
echo "Sent request with bad User-Agent."

# 3. Trigger Aggressive Crawler
echo -e "${YELLOW}[3/4] Triggering 'http-crawl-non_statics' (100 distinct paths)...${NC}"
for i in {1..100}; do
    curl -s -o /dev/null "${TARGET_URL}/test-bot-$i.php"
    sleep 0.1
    if [ $((i % 20)) -eq 0 ]; then echo "Sent $i requests..."; fi
done

echo "Waiting for CrowdSec to process logs (15 seconds)..."
sleep 15

# 4. Verify Block
echo -e "${YELLOW}[4/4] Verifying the block...${NC}"

if is_blocked; then
    echo -e "${GREEN}SUCCESS: CrowdSec detected the attack and added a decision!${NC}"
    
    echo "Waiting for bouncer sync (5 seconds)..."
    sleep 5
    STATUS_BLOCKED=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET_URL}/")
    
    if [ "$STATUS_BLOCKED" -eq "403" ]; then
        echo -e "${GREEN}SUCCESS: BunkerWeb returned 403 Forbidden! Bot is blocked.${NC}"
    else
        echo -e "${RED}FAILURE: BunkerWeb did NOT block the request. Status: ${STATUS_BLOCKED}${NC}"
    fi
else
    echo -e "${RED}FAILURE: CrowdSec did NOT detect the attack.${NC}"
    echo "Current decisions:"
    sudo docker exec "$CROWDSEC_ID" cscli decisions list
fi

# --- Cleanup & Restoration ---
echo -e "\n${BLUE}=== Post-Test Cleanup ===${NC}"

if [ -f "/tmp/crowdsec_whitelist_disabled" ] || [ ! -z "$HAS_WHITELIST" ]; then
    echo "Restoring CrowdSec whitelist..."
    sudo docker exec "$CROWDSEC_ID" mv "${WHITELIST_PATH}.bak" "$WHITELIST_PATH" 2>/dev/null
    sudo docker restart "$CROWDSEC_ID" > /dev/null
    echo "CrowdSec restored. Waiting 5 seconds for bouncer to reconnect..."
    sleep 5
    # Update container ID after restart just in case
    CROWDSEC_ID=$(sudo docker compose -f "${PROJECT_ROOT}/docker-compose.yml" ps -q crowdsec)
fi

echo "Removing decision for ${ATTACKER_IP} in CrowdSec..."
sudo docker exec "$CROWDSEC_ID" cscli decisions delete --ip "${ATTACKER_IP}" > /dev/null

echo "Removing local ban for ${ATTACKER_IP} in BunkerWeb..."
sudo docker exec "$BUNKERWEB_ID" bwcli unban "${ATTACKER_IP}" > /dev/null

echo -e "${GREEN}Cleanup completed.${NC}"
