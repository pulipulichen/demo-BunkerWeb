#!/bin/bash

cd $(dirname $0)

sudo docker compose down -v
rm -f bunkerweb/.env.crowdsec
./startup.sh