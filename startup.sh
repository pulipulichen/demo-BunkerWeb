#!/bin/bash

cd $(dirname $0)

sudo docker compose down
sudo docker compose up --build -d
sudo docker compose logs -f