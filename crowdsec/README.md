建立金鑰
```
docker exec -it $(docker compose ps -q crowdsec) cscli bouncers add bunkerweb
```

檢查有沒有生效

```
docker exec -it $(docker compose ps -q crowdsec) cscli metrics
```