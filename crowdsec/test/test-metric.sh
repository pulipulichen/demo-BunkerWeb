#!/bin/bash

cd $(dirname $0)

# cd ../..

# sudo docker compose ps -q crowdsec

sudo docker exec -it $(sudo docker compose ps -q crowdsec) cscli metrics

# 檢查有沒有生效

# ```
# docker exec -it $(docker compose ps -q crowdsec) cscli metrics
# ```