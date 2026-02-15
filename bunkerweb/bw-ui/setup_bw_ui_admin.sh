#!/bin/bash

# Navigate to the script's directory
cd "$(dirname "$0")"

# 1. Copy .env.example to .env if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env from example..."
    cp .env.example .env
fi