#!/bin/bash

# Navigate to the script's directory
cd "$(dirname "$0")"

# 1. Copy .env.crowdsec.example to .env.crowdsec if it doesn't exist
if [ ! -f .env.crowdsec ]; then
    echo "Creating .env.crowdsec from example..."
    cp .env.crowdsec.example .env.crowdsec
fi