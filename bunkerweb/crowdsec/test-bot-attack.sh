#!/bin/bash

# Configuration
TARGET_URL="http://localhost:8080"
ATTACKER_IP="10.20.30.1"
CROWDSEC_CONTAINER="demo-bunkerweb-crowdsec-1"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Complex Bot Attack Simulation ===${NC}"

# Function to check if IP is blocked in CrowdSec
is_blocked() {
    sudo docker exec "$CROWDSEC_CONTAINER" cscli decisions list --ip "$ATTACKER_IP" | grep -q "$ATTACKER_IP"
}

# 1. Test Normal Request
echo -e "${YELLOW}[1/4] Sending normal request from ${ATTACKER_IP}...${NC}"
STATUS=$(curl -s -H "X-Forwarded-For: ${ATTACKER_IP}" -o /dev/null -w "%{http_code}" "${TARGET_URL}/")
if [ "$STATUS" -eq "200" ]; then
    echo -e "${GREEN}SUCCESS: Initial request returned 200 OK.${NC}"
else
    echo -e "${RED}FAILURE: Initial request returned ${STATUS}.${NC}"
    exit 1
fi

# 2. Trigger Bad User-Agent
echo -e "${YELLOW}[2/4] Triggering 'http-bad-user-agents' (UA: Masscan/1.3)...${NC}"
curl -s -H "X-Forwarded-For: ${ATTACKER_IP}" -A "Masscan/1.3" -o /dev/null "${TARGET_URL}/"
echo "Sent request with bad User-Agent."

# 3. Trigger Aggressive Crawler
echo -e "${YELLOW}[3/4] Triggering 'http-crawl-non_statics' (100 distinct paths with 0.1s delay)...${NC}"
for i in {1..100}; do
    curl -s -H "X-Forwarded-For: ${ATTACKER_IP}" -o /dev/null "${TARGET_URL}/path$i.php"
    sleep 0.1
    if [ $((i % 20)) -eq 0 ]; then echo "Sent $i requests..."; fi
done

echo "Waiting for CrowdSec to process logs (10 seconds)..."
sleep 10

# 4. Verify Block
echo -e "${YELLOW}[4/4] Verifying the block...${NC}"

if is_blocked; then
    echo -e "${GREEN}SUCCESS: CrowdSec has added a decision for ${ATTACKER_IP}.${NC}"
    
    echo "Testing if BunkerWeb now blocks the request (5 seconds sync wait)..."
    sleep 5
    STATUS_BLOCKED=$(curl -s -H "X-Forwarded-For: ${ATTACKER_IP}" -o /dev/null -w "%{http_code}" "${TARGET_URL}/")
    
    if [ "$STATUS_BLOCKED" -eq "403" ]; then
        echo -e "${GREEN}SUCCESS: BunkerWeb returned 403 Forbidden! The bot is blocked.${NC}"
    else
        echo -e "${RED}FAILURE: BunkerWeb did NOT block the request. Status: ${STATUS_BLOCKED}${NC}"
        echo "Hint: Check if the bouncer is correctly synchronizing from CrowdSec."
    fi
else
    echo -e "${RED}FAILURE: CrowdSec did NOT detect the attack.${NC}"
    echo "Showing current decisions:"
    sudo docker exec "$CROWDSEC_CONTAINER" cscli decisions list
fi

# Cleanup
echo -e "\n${BLUE}=== Post-Test Cleanup ===${NC}"
echo "Removing decision for ${ATTACKER_IP}..."
sudo docker exec "$CROWDSEC_CONTAINER" cscli decisions delete --ip "$ATTACKER_IP" > /dev/null
echo -e "${GREEN}Cleanup completed.${NC}"
