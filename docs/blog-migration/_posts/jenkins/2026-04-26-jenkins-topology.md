---
layout: post
title: "Jenkins 部署拓扑：通用逻辑、阿里云 ACK、本地 IDC"
date: 2026-04-26 10:00:00 +0800
categories: [jenkins, 架构]
tags: [jenkins, 架构, 拓扑]
description: "Jenkins 控制器与 Agent 的逻辑拓扑，以及阿里云 ACK 与本地 IDC 两种落地形态。"
slug: jenkins-topology
---

## 1. 通用逻辑拓扑（两方案共享）

```
┌─────────────────────────────────────────────────────────────────────┐
│                          用户 / 工程师终端                            │
│   浏览器(HTTPS)        jk CLI (HTTPS + API Token)     CI 机器人       │
└──────────────┬──────────────────┬─────────────────────┬─────────────┘
               │                  │                     │
               ▼                  ▼                     ▼
        ┌──────────────────────────────────────────────────────┐
        │   零信任网关 / VPN（Tailscale / Teleport / Cloudflare）│  ← 公司外可选
        └──────────────────────────────┬───────────────────────┘
                                       │
                                       ▼
        ┌──────────────────────────────────────────────────────┐
        │      反向代理（Nginx / Traefik / ALB）+ TLS 终止      │
        │      Host: jenkins.corp.example.com                   │
        └──────────────────────────────┬───────────────────────┘
                                       │
                                       ▼
        ┌──────────────────────────────────────────────────────┐
        │              Jenkins Controller (Master)              │
        │  - JCasC 加载配置                                      │
        │  - LDAP 认证 + Role Strategy 授权                      │
        │  - Vault 取密钥                                        │
        │  - Prometheus metrics endpoint                        │
        │  PV: jenkins_home  (持久化)                            │
        └─────┬──────────────┬─────────────┬─────────────┬─────┘
              │JNLP/HTTPS    │             │             │
              ▼              ▼             ▼             ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐
        │ K8s Pod  │  │ Linux VM │  │ Windows  │  │ GPU/Build    │
        │ Agent    │  │ Agent    │  │ Agent    │  │ Heavy Agent  │
        │ (动态)   │  │ (静态)   │  │ (静态)   │  │ (静态)       │
        └──────────┘  └──────────┘  └──────────┘  └──────────────┘

        外部依赖（旁路）：
          ├─ LDAP / AD              （认证）
          ├─ HashiCorp Vault         （密钥）
          ├─ Nexus / Artifactory     （制品/缓存）
          ├─ GitLab / Bitbucket      （SCM + Webhook）
          ├─ Prometheus + Grafana    （监控）
          ├─ Loki / ELK              （日志）
          └─ 对象存储 (OSS/S3/MinIO) （备份）
```

## 2. 方案 A：阿里云 ACK 物理拓扑

```
                          公网 (可选)
                            │
                            ▼
                ┌────────────────────────┐
                │   阿里云 SLB (ALB/NLB) │  ← 内网或公网，按合规要求
                │   TLS 证书托管在 SLB 或 │
                │   ACK Ingress          │
                └───────────┬────────────┘
                            │
                            ▼
        ┌────────────────────────────────────────────┐
        │      ACK 集群 (3+ master, N worker)        │
        │  ┌───────────────┐  ┌────────────────────┐ │
        │  │ ingress-nginx │  │ cert-manager       │ │
        │  └───────────────┘  └────────────────────┘ │
        │                                            │
        │  Namespace: jenkins                        │
        │  ┌───────────────────────────────────────┐ │
        │  │ Helm release: jenkins/jenkins         │ │
        │  │  ├─ controller StatefulSet (1 副本)   │ │
        │  │  │   PVC → 阿里云 NAS (RWX) 50Gi      │ │
        │  │  ├─ Service (ClusterIP)               │ │
        │  │  └─ Ingress → jenkins.corp.example.com│ │
        │  │                                       │ │
        │  │ k8s plugin → 动态 Pod agent            │ │
        │  └───────────────────────────────────────┘ │
        │                                            │
        │  Namespace: monitoring (kube-prometheus)   │
        │  Namespace: vault (可选, 或用阿里云 KMS)   │
        └────────────────────────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────────┐
              │  阿里云 OSS (备份, 加密)     │
              │  阿里云 ACR (镜像)           │
              │  阿里云 NAS (jenkins_home)   │
              │  阿里云 RDS (可选, 审计 DB)  │
              └─────────────────────────────┘

  企业内网 ←(VPN / 专线 / 高速通道)→ ACK VPC
       │
       ├─ AD/LDAP 服务器
       └─ 内部 GitLab / Nexus
```

## 3. 方案 B：本地 IDC 局域网集群拓扑

```
        办公网 / VPN                       生产 IDC
            │                                 │
            ▼                                 │
  ┌────────────────────┐                      │
  │ 内部 DNS (CoreDNS) │  jenkins.idc.local   │
  │ 内部 CA (step-ca)  │  → 10.0.1.20 (VIP)   │
  └────────────────────┘                      │
            │                                 │
            ▼                                 ▼
  ┌────────────────────────────────────────────────────────┐
  │  Keepalived VIP 10.0.1.20 + Nginx (主/备 双机)         │
  │  TLS 终止, 访问日志, WAF (modsecurity 可选)            │
  └─────────────────────────┬──────────────────────────────┘
                            │
                            ▼
  ┌────────────────────────────────────────────────────────┐
  │  Jenkins Controller VM   (10.0.1.10)                   │
  │   - Ubuntu 22.04 LTS, systemd                          │
  │   - Docker Compose 起 jenkins/jenkins:lts-jdk21        │
  │   - 挂载 /srv/jenkins_home → 本地 SSD (或 NFS)         │
  │   - 备份: cron + restic → MinIO/对象存储                │
  └─┬───────────────┬───────────────┬─────────────────────┘
    │ JNLP 50000    │ SSH 22        │ JNLP/SSH
    ▼               ▼               ▼
  ┌─────────┐  ┌──────────┐  ┌─────────────┐
  │ Linux   │  │ Windows  │  │ GPU 节点    │
  │ Agent×N │  │ Agent×M  │  │ Agent×K     │
  │ VM/裸机 │  │ 物理机   │  │ 物理机      │
  └─────────┘  └──────────┘  └─────────────┘

  旁路：
    AD/LDAP 服务器 (10.0.2.5)
    GitLab          (10.0.3.10)
    Nexus           (10.0.3.20)
    Prometheus/Grafana (10.0.4.x)
    MinIO 备份      (10.0.5.10)
```

> Jenkins 控制器原生不支持 active-active HA。方案 B 的高可用做法是 **冷备**：
> 第二台 VM 同步 `jenkins_home`，VIP 切换。要真正 HA 需 CloudBees CI 商业版。

## 4. 端口与协议

| 端口 | 协议 | 用途 | 暴露范围 |
|---:|---|---|---|
| 443 | HTTPS | Web UI / REST API / `jk` CLI | 用户网段 / VPN |
| 80 | HTTP | 跳转 → 443（可禁用） | 同上 |
| 50000 | TCP（JNLP） | inbound agent 连接 | 仅 agent 网段 |
| 22 | SSH | controller → agent（SSH agent 模式） | controller → agent |
| 8080 | HTTP | Jenkins 内部端口 | 仅集群内 / 反代后端 |
| 9100 | HTTP | node_exporter（可选） | 监控网段 |

## 5. 数据流

1. 用户登录：浏览器/`jk` → 反代 → Jenkins → LDAP 验证 → 颁发 cookie / 接受 API token。
2. 触发构建：Webhook（GitLab/GitHub）→ 反代 → Jenkins → 调度到 agent。
3. 凭据使用：Pipeline `withVault {}` → Jenkins Vault plugin → Vault → 临时注入到 agent 环境变量。
4. 备份：cron → restic → 对象存储（OSS / MinIO），加密 + 异地副本。
5. 监控：Prometheus scrape `https://.../prometheus`（带 token）→ Grafana。
6. 日志：controller stdout / `$JENKINS_HOME/logs/` → Filebeat → Loki/ELK。
