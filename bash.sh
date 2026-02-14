#!/bin/bash

cd $(dirname $0)

# 我要進去執行中的 php 裡面，做bash
docker exec -it $(docker compose ps -q php) bash
