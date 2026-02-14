#!/bin/bash

# 如果沒有docker compose up 的話，先up起來

# Check if docker compose services are running
if [ -z "$(docker compose ps --services --filter "status=running")" ]; then
  echo "Docker Compose services are not running. Starting them up..."
  docker compose up -d
else
  echo "Docker Compose services are already running."
fi

docker compose logs -f
