---
layout: post
title: "在本地 IDC 局域网部署 Jenkins（VM + Docker Compose）"
date: 2026-04-26 10:00:00 +0800
categories: [jenkins, 架构]
tags: [jenkins, 架构, 部署, docker, idc]
description: "基于 VM + Docker Compose 在本地 IDC 落地 Jenkins 控制器的实践手册。"
slug: jenkins-deploy-idc-lan
---

适用于小到中型团队、传统机房环境，或对 K8s 暂无运维能力的场景。

## 1. 前置准备

- 2 台 VM 给控制器（主+冷备），4C8G + 200GB SSD 起步，Ubuntu 22.04 LTS。
- N 台 VM/物理机做 agent，按工种打标签：`linux`, `windows`, `gpu`, `build-heavy`。
- 1 台 VM（或与 LB 复用）做 Nginx + Keepalived。
- 内部 DNS：`jenkins.idc.local → 10.0.1.20`（VIP）。
- 内部 CA 已能签发证书，或 step-ca 已部署。
- LDAP 信息齐备。
- MinIO 或现有 S3 可作为备份目的地。

## 2. 控制器主机（10.0.1.10）

### 2.1 系统基线

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin ufw fail2ban unattended-upgrades
sudo systemctl enable --now docker
sudo ufw allow 22/tcp
sudo ufw allow from 10.0.10.0/24 to any port 50000 proto tcp
sudo ufw enable
```

### 2.2 目录与挂载

```bash
sudo mkdir -p /srv/jenkins/{home,casc,backup}
sudo chown -R 1000:1000 /srv/jenkins/home /srv/jenkins/casc
```

### 2.3 `/srv/jenkins/docker-compose.yml`

```yaml
services:
  jenkins:
    image: jenkins/jenkins:lts-jdk21
    container_name: jenkins
    restart: unless-stopped
    user: "1000:1000"
    environment:
      JAVA_OPTS: "-Djenkins.install.runSetupWizard=false -Dhudson.model.DirectoryBrowserSupport.CSP=\"sandbox; default-src 'self'\""
      CASC_JENKINS_CONFIG: /var/jenkins_casc
    volumes:
      - /srv/jenkins/home:/var/jenkins_home
      - /srv/jenkins/casc:/var/jenkins_casc:ro
    ports:
      - "127.0.0.1:8080:8080"     # 仅本机，由 nginx 反代
      - "10.0.1.10:50000:50000"   # JNLP 仅监听内网 IP
```

### 2.4 JCasC：`/srv/jenkins/casc/jenkins.yaml`

```yaml
jenkins:
  systemMessage: "Managed by JCasC. Changes via Git PR."
  numExecutors: 0
  mode: EXCLUSIVE
  authorizationStrategy:
    roleBased:
      roles:
        global:
          - name: "admin"
            permissions: ["Overall/Administer"]
            assignments: ["GROUP:cn=ci-admins,ou=Groups,dc=corp,dc=example,dc=com"]
          - name: "viewer"
            permissions: ["Overall/Read"]
            assignments: ["GROUP:cn=all-staff,ou=Groups,dc=corp,dc=example,dc=com"]
  securityRealm:
    ldap:
      configurations:
        - server: "ldaps://ldap.corp.example.com:636"
          rootDN: "dc=corp,dc=example,dc=com"
          userSearchBase: "ou=Users"
          userSearch: "sAMAccountName={0}"
          groupSearchBase: "ou=Groups"
          managerDN: "cn=jenkins-bind,ou=ServiceAccounts,dc=corp,dc=example,dc=com"
          managerPasswordSecret: "${LDAP_MANAGER_PASSWORD}"
unclassified:
  location:
    url: https://jenkins.idc.local
    adminAddress: ops@corp.example.com
```

把 `LDAP_MANAGER_PASSWORD` 等敏感值放到 `/srv/jenkins/casc/secrets.env`，由 docker-compose `env_file` 注入，并 `chmod 600`。

### 2.5 启动并初始化

```bash
cd /srv/jenkins
docker compose up -d
docker compose logs -f jenkins   # 等到 "Jenkins is fully up and running"
```

## 3. 反向代理 + VIP（LB 节点）

### 3.1 安装

```bash
sudo apt install -y nginx keepalived
```

### 3.2 `/etc/nginx/sites-available/jenkins.conf`

```nginx
upstream jenkins_upstream {
  server 10.0.1.10:8080 max_fails=3 fail_timeout=10s;
  # 备机：手动切换时启用
  # server 10.0.1.11:8080 backup;
  keepalive 32;
}

server {
  listen 80;
  server_name jenkins.idc.local;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl http2;
  server_name jenkins.idc.local;

  ssl_certificate     /etc/ssl/jenkins/fullchain.pem;
  ssl_certificate_key /etc/ssl/jenkins/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;

  client_max_body_size 200m;
  proxy_buffering off;
  proxy_request_buffering off;
  proxy_read_timeout 300s;
  proxy_send_timeout 300s;

  location / {
    proxy_pass http://jenkins_upstream;
    proxy_http_version 1.1;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Connection        "";
  }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/jenkins.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### 3.3 `/etc/keepalived/keepalived.conf`（主）

```conf
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 110
    advert_int 1
    authentication { auth_type PASS; auth_pass changeMe; }
    virtual_ipaddress { 10.0.1.20/24 }
}
```

备机 `state BACKUP`、`priority 100`。

```bash
sudo systemctl enable --now keepalived
```

## 4. Agent 接入

### 4.1 Linux SSH agent

控制器 UI → Manage Nodes → New Node → Permanent Agent；或在 JCasC 中声明：

```yaml
jenkins:
  nodes:
    - permanent:
        name: "agent-linux-01"
        labelString: "linux build-heavy"
        remoteFS: "/var/lib/jenkins"
        launcher:
          ssh:
            host: "10.0.10.11"
            port: 22
            credentialsId: "ssh-agent-key"
```

### 4.2 Windows JNLP agent

1. 在 Jenkins 上创建 inbound agent（`agent-win-01`，标签 `windows`）。
2. 在 Windows 上以服务方式启动 `agent.jar`，连接 `https://jenkins.idc.local`，端口 50000（需在 LB/防火墙放行 agent 网段到 controller 50000）。

> JNLP 50000 端口**不要**经过 nginx，agent 直接连控制器内网 IP（`10.0.1.10:50000`）。

## 5. 备份

控制器 crontab：

```bash
0 2 * * * /usr/local/bin/restic-backup.sh >> /var/log/jenkins-backup.log 2>&1
```

`/usr/local/bin/restic-backup.sh`：

```bash
#!/bin/bash
set -euo pipefail
export RESTIC_REPOSITORY="s3:http://minio.idc.local/jenkins-backup"
export RESTIC_PASSWORD_FILE=/etc/restic/password
export AWS_ACCESS_KEY_ID=$(cat /etc/restic/ak)
export AWS_SECRET_ACCESS_KEY=$(cat /etc/restic/sk)

restic backup /srv/jenkins/home \
  --exclude='workspace/*' \
  --exclude='caches/*' \
  --exclude='*.log' \
  --tag jenkins-home

restic forget --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune
```

`/etc/restic/*` 权限 `600`，属主 root。

## 6. 冷备机与切换演练

- 备机用同一份 `docker-compose.yml`，**先不启动**。
- 主控制器 cron 每 30 分钟把 `/srv/jenkins/home` rsync 到备机：

  ```bash
  */30 * * * * rsync -aH --delete --exclude='workspace/' --exclude='caches/' \
    /srv/jenkins/home/ jenkins-standby:/srv/jenkins/home/
  ```

- 演练：停主 → nginx upstream 改 backup → 备机 `docker compose up -d` → 验证。

## 7. 监控 / 日志

- Jenkins 安装 Prometheus 插件，Prometheus scrape `https://jenkins.idc.local/prometheus`（带 token）。
- node_exporter 部署到所有 VM。
- Filebeat 采集 `/srv/jenkins/home/logs/`、`/var/log/nginx/` 推到 Loki。
- Grafana 导入：Jenkins (9964)、Node Exporter (1860)、Nginx (12708)。

## 8. `jk` 客户端验证

```bash
jk auth login --server https://jenkins.idc.local --user $USER --token <PAT>
jk job ls
jk run ls --since 24h
jk run trigger smoke-test --watch
```

## 9. 故障排查速查

| 现象 | 排查点 |
|---|---|
| 浏览器证书报错 | 内部 CA 是否分发；证书 SAN 是否含 `jenkins.idc.local` |
| LDAP 登录失败 | `ldapsearch -H ldaps://... -D <managerDN> -W -b <userBase> '(sAMAccountName=alice)'` |
| Webhook 不触发 | 反代是否屏蔽了源 IP；Jenkins 收到的 X-Forwarded-For 是否正确 |
| Agent 掉线 | 50000 端口、controller 与 agent 时间同步、JNLP secret 是否正确 |
| 构建慢 | 检查磁盘 IOPS、`workspace` 是否在 SSD、是否被 swap |
