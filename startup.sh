#!/bin/bash

cd $(dirname $0)

git pull

docker compose down
docker compose up --build -d
docker compose logs -f