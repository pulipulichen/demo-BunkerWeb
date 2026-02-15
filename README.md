# demo-BunkerWeb
A project demonstrating how to use BunkerWeb as a firewall for Nginx servers.

# What is it?

This project demonstrates the integration of BunkerWeb with Nginx to build a robust Web Application Firewall (WAF). The input data consists of Nginx base configurations, security policy parameters, and real-time network traffic requests; through BunkerWeb's security processing and filtering, the output is a hardened web server environment capable of automatically identifying and blocking malicious attacks such as SQL injection and Cross-Site Scripting (XSS), ensuring the overall security and stability of web services.

#TODO 敘述的地方還要加上 Crowdsec

# 如何整合到自己的網站

修改 docker-compose.yml ，修改裡面 nginx 跟 php 的資料

# 如何啟動

環境 Ubuntu 24.04，Docker version 28.3.3, build 980b856

執行 startup.sh

裡面會執行的內容

1. 關閉之前執行的容器
2. 啟動並進行編譯
3. 觀察 logs
4. 看到  `[INIT-WORKER] BunkerWeb is ready to fool hackers ! 🚀, context: ngx.timer` 就表示啟動完成。
![[Pasted image 20260215144257.png]]

使用者的操作：
1. 開啟 http://localhost:8080
2. 在   `[INIT-WORKER] BunkerWeb is ready to fool hackers ! 🚀, context: ngx.timer`  出現之前，需要等待 BunkerWeb準備完成，大概30秒
![[Pasted image 20260215144242.png]]
3. 可以正常連線
![[Pasted image 20260215144414.png]]

# 如何驗證 BunkerWeb 跟 Crowdsec能夠正常連線

執行 `./test/bunkerweb/ban-bot-attack.sh` ，也可以用 npm 指令執行 `npm run test` 。

![[Pasted image 20260215145154.png]]


# 如何修改 BunkerWeb Port 8080

#TODO 看Docker Compose，直接幫我寫完