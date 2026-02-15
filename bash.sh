#!/bin/bash

cd $(dirname $0)

# Check if docker compose services are running
if [ -z "$(sudo docker compose ps --services --filter "status=running")" ]; then
  echo "Docker Compose services are not running. Starting them up..."
  sudo docker compose up -d
else
  echo "Docker Compose services are already running."
fi

docker exec -it $(docker compose ps -q nginx) bash
