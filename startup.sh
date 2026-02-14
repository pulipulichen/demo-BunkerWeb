#!/bin/bash

cd $(dirname $0)

touch bunkerweb/.env.crowdsec

sudo docker compose down

sleep 5

sudo docker compose up --build -d

# Check/Generate CrowdSec API Key
sudo ./bunkerweb/check_crowdsec_api_key.sh &

# clear
sudo docker compose logs -f