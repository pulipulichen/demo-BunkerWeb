#!/bin/bash

# Configuration
TARGET_URL="http://localhost:8080"
TEST_IP="10.20.30.1" # The IP address seen in headers (adjust if needed)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== CrowdSec + BunkerWeb Verification ===${NC}"

# 1. Check Connectivity
echo -e "${YELLOW}[1/4] Checking BunkerWeb logs for NEW CrowdSec errors...${NC}"
# Only check errors in the last 30 seconds to avoid picking up stale errors from before the fix
ERROR_LOG=$(sudo docker logs demo-bunkerweb-bunkerweb-instance-1 --since 30s 2>&1 | grep "bouncer error" | tail -n 1)

if [ ! -z "$ERROR_LOG" ]; then
    echo -e "${RED}FAILURE: Recent CrowdSec error found in logs:${NC}"
    echo "$ERROR_LOG"
    echo "Please check your CROWDSEC_API_KEY and connectivity."
    exit 1
else
    echo -e "${GREEN}SUCCESS: No CrowdSec errors found in recent logs.${NC}"
fi

# 2. Test Normal Request
echo -e "${YELLOW}[2/4] Testing normal request...${NC}"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET_URL}/")
if [ "$STATUS" -eq "200" ]; then
    echo -e "${GREEN}SUCCESS: Normal request returned 200 OK.${NC}"
else
    echo -e "${RED}FAILURE: Normal request returned ${STATUS}.${NC}"
    exit 1
fi

# 3. Test Manual Ban (Fastest way to verify)
echo -e "${YELLOW}[3/4] Testing manual ban for IP ${TEST_IP}...${NC}"

# Add manual decision
sudo docker exec demo-bunkerweb-crowdsec-1 cscli decisions add --ip "$TEST_IP" --reason "test" --duration 1m > /dev/null

echo "Waiting for bouncer to sync (5 seconds)..."
sleep 5

# Test request
STATUS_BLOCKED=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET_URL}/")

# Clean up ban immediately
sudo docker exec demo-bunkerweb-crowdsec-1 cscli decisions delete --ip "$TEST_IP" > /dev/null

if [ "$STATUS_BLOCKED" -eq "403" ]; then
    echo -e "${GREEN}SUCCESS: Manual ban verified. Request was blocked with 403.${NC}"
else
    echo -e "${RED}FAILURE: Request was NOT blocked by manual ban. Status: ${STATUS_BLOCKED}${NC}"
    echo "Hint: Check if USE_CROWDSEC=yes is set and bouncer is valid."
fi

# 4. Simulating "Malicious" Request (Path Traversal)
echo -e "${YELLOW}[4/4] Simulating Path Traversal Attack (/etc/passwd)...${NC}"
STATUS_ATTACK=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET_URL}/etc/passwd")

if [ "$STATUS_ATTACK" -eq "403" ]; then
    echo -e "${GREEN}SUCCESS: Attack was blocked with 403.${NC}"
    echo -e "${BLUE}Note: This might be blocked by ModSecurity before CrowdSec sees it.${NC}"
else
    echo -e "${RED}WARNING: Attack request was NOT blocked. Status: ${STATUS_ATTACK}${NC}"
    echo "Check if ModSecurity (USE_MODSECURITY) is enabled."
fi

echo -e "\n${BLUE}=== Verification Completed ===${NC}"
