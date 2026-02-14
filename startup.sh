#!/bin/bash

cd $(dirname $0)

sudo docker compose down
sudo docker compose up --build -d

clear
sudo docker compose logs -f