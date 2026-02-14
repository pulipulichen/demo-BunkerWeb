#!/bin/bash

# ==============================================================================
# Title: BunkerWeb + CrowdSec Verification Script
# Description: Tests if CrowdSec is correctly blocking malicious requests 
#              on a BunkerWeb instance running at localhost:8080.
# OS: Ubuntu 24.04
# ==============================================================================

# Configuration
TARGET_URL="http://localhost:8080"
MALICIOUS_PATH="/etc/passwd"
NORMAL_PATH="/"
EXPECTED_NORMAL_STATUS="200"
EXPECTED_BLOCKED_STATUS="403"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== BunkerWeb & CrowdSec Security Test ===${NC}"
echo -e "Target: ${TARGET_URL}"
echo ""

# 1. Check if the service is up
echo -e "${YELLOW}[1/3] Testing normal connectivity...${NC}"
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET_URL}${NORMAL_PATH}")

if [ "$STATUS_CODE" -eq "$EXPECTED_NORMAL_STATUS" ]; then
    echo -e "${GREEN}SUCCESS: Service is reachable. Status: ${STATUS_CODE}${NC}"
else
    echo -e "${RED}FAILURE: Service is not responding with 200 OK. Status: ${STATUS_CODE}${NC}"
    echo "Please check if BunkerWeb is running on localhost:8080."
    exit 1
fi

echo ""

# 2. Simulate a Malicious Request (Path Traversal)
# Most WAFs and CrowdSec scenarios will flag access to /etc/passwd immediately
echo -e "${YELLOW}[2/3] Simulating Malicious Request (${MALICIOUS_PATH})...${NC}"
ATTACK_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${TARGET_URL}${MALICIOUS_PATH}")

if [ "$ATTACK_STATUS" -eq "$EXPECTED_BLOCKED_STATUS" ]; then
    echo -e "${GREEN}SUCCESS: The malicious request was BLOCKED. Status: ${ATTACK_STATUS}${NC}"
else
    echo -e "${RED}WARNING: The malicious request was NOT blocked. Status: ${ATTACK_STATUS}${NC}"
    echo "This suggests the WAF or CrowdSec rules are not active for this path."
fi

echo ""

# 3. Verify CrowdSec Decisions (Optional - Requires cscli access)
echo -e "${YELLOW}[3/3] Checking CrowdSec status...${NC}"

# Note: We check if 'cscli' exists. If BunkerWeb is in Docker, 
# you might need 'docker exec bunkerweb cscli decisions list'
if command -v cscli &> /dev/null; then
    echo "Found local cscli. Fetching active decisions..."
    cscli decisions list
elif command -v docker &> /dev/null; then
    echo "Checking if BunkerWeb is running in Docker to run cscli..."
    CONTAINER_ID=$(sudo docker ps -q -f "name=bunkerweb")
    if [ ! -z "$CONTAINER_ID" ]; then
        echo "Found BunkerWeb container. Fetching decisions from inside..."
        sudo docker exec "$CONTAINER_ID" cscli decisions list
    else
        echo "BunkerWeb container not found. Skipping cscli check."
    fi
else
    echo "cscli command not found. Please verify decisions manually."
fi

echo ""
echo -e "${BLUE}=== Test Completed ===${NC}"