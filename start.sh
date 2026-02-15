#!/bin/bash

cd $(dirname $0)

./bunkerweb/setup_crowdsec_api_key.sh
./bunkerweb/bw-ui/setup_bw_ui_admin.sh

sudo docker compose down
sudo docker compose up --build -d

# Check/Generate CrowdSec API Key
sudo ./bunkerweb/check_crowdsec_api_key.sh

# clear
sudo docker compose logs -f