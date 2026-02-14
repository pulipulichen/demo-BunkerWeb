#!/bin/bash

# Navigate to the script's directory
cd "$(dirname "$0")"

# 1. Copy .env.crowdsec.example to .env.crowdsec if it doesn't exist
if [ ! -f .env.crowdsec ]; then
    echo "Creating .env.crowdsec from example..."
    cp .env.crowdsec.example .env.crowdsec
fi

# Find the crowdsec container name (it might have a prefix or suffix)
sleep 5
CROWDSEC_CONTAINER=$(sudo docker ps --format '{{.Names}}' | grep crowdsec | head -n 1)

if [ -z "$CROWDSEC_CONTAINER" ]; then
    echo "Error: CrowdSec container not found."
    exit 1
fi

# 2. Add/Refresh CrowdSec API Key
echo "Checking CrowdSec API key status (using container: $CROWDSEC_CONTAINER)..."

# Check if .env.crowdsec has a valid-looking API key (not the placeholder)
CURRENT_API_KEY=$(grep "^CROWDSEC_API_KEY=" .env.crowdsec | cut -d'=' -f2)
PLACEHOLDER="12345678901234567890123456789012"

# Check if bouncer already exists in CrowdSec
# Use jq if available, otherwise fallback to a more robust grep for JSON
if command -v jq >/dev/null 2>&1; then
    BOUNCER_EXISTS=$(sudo docker exec "$CROWDSEC_CONTAINER" cscli bouncers list -o json | jq -r '.[] | select(.name == "bunkerweb") | .name' | grep -q "bunkerweb" && echo "yes" || echo "no")
else
    # Fallback to grep if jq is not installed
    BOUNCER_EXISTS=$(sudo docker exec "$CROWDSEC_CONTAINER" cscli bouncers list -o json | grep -q "\"name\":[[:space:]]*\"bunkerweb\"" && echo "yes" || echo "no")
fi

if [ "$BOUNCER_EXISTS" = "yes" ] && [ "$CURRENT_API_KEY" != "$PLACEHOLDER" ] && [ -n "$CURRENT_API_KEY" ]; then
    echo "Bouncer 'bunkerweb' already exists and API key is set. Skipping recreation."
    exit 0
fi

echo "Generating/Refreshing CrowdSec API key..."

# Remove existing bouncer if it exists to avoid conflicts (only if we need to refresh)
if [ "$BOUNCER_EXISTS" = "yes" ]; then
    sudo docker exec "$CROWDSEC_CONTAINER" cscli bouncers delete bunkerweb > /dev/null 2>&1
fi

# Add new bouncer and capture the API key
NEW_API_KEY=$(sudo docker exec "$CROWDSEC_CONTAINER" cscli bouncers add bunkerweb -o raw)

if [ -z "$NEW_API_KEY" ]; then
    echo "Error: Failed to generate API key."
    exit 1
fi

echo "Updating .env.crowdsec with new API key..."

# 3. Update the API key in .env.crowdsec
# Using sed to replace the CROWDSEC_API_KEY value
if grep -q "CROWDSEC_API_KEY=" .env.crowdsec; then
    sed -i "s|^CROWDSEC_API_KEY=.*|CROWDSEC_API_KEY=$NEW_API_KEY|" .env.crowdsec
else
    echo "CROWDSEC_API_KEY=$NEW_API_KEY" >> .env.crowdsec
fi

echo "Done! API key updated to: $NEW_API_KEY"
echo "Restarting BunkerWeb containers to apply changes..."

# Go back to the root directory to run docker compose
cd ..
sudo docker compose down bunkerweb-instance bw-scheduler
sudo docker compose up -d bunkerweb-instance bw-scheduler

echo "Containers restarted successfully."