#!/bin/bash

cd $(dirname $0)


sudo docker compose down -v > /dev/null 2>&1

cp -f bunkerweb/.env.crowdsec.example bunkerweb/.env.crowdsec

./start.sh