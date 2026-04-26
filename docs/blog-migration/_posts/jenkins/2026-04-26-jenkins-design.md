---
layout: post
title: "Jenkins 平台设计：HA / 权限 / 备份 / 网络 / 合规 / LDAP"
date: 2026-04-26 10:00:00 +0800
categories: [jenkins, 架构]
tags: [jenkins, 架构, 设计, HA, LDAP]
description: "Jenkins 平台关键设计决策：高可用、RBAC、备份恢复、网络分层、合规与 LDAP 接入。"
slug: jenkins-design
---

## 1. 设计目标与非目标

### 目标
- 工程师可通过浏览器与 `jk` CLI 安全访问 Jenkins。
- **配置即代码**（JCasC + Jenkinsfile + Job DSL），可重建、可审计。
- 故障 30 分钟内恢复（RTO=30 min，RPO=24 h；可按需缩短至 1 h）。
- 所有访问走 TLS、走 LDAP 认证、走 RBAC 授权。
- 密钥不落明文。
- 用户登录后能直观看到"自己的任务"。

### 非目标
- 不追求 active-active 多活（OSS Jenkins 不支持，需 CloudBees CI）。
- 不替代企业级 DevOps 平台（Jenkins X、Argo Workflows 等）。

## 2. 组件选型

| 类别 | 选型 | 备注 |
|---|---|---|
| 控制器镜像 | `jenkins/jenkins:lts-jdk21` | LTS 长期支持 |
| 安装方式（A） | Helm chart `jenkins/jenkins` | 官方维护 |
| 安装方式（B） | Docker Compose + systemd | 简单可控 |
| 反向代理（A） | ingress-nginx + cert-manager | K8s 生态标配 |
| 反向代理（B） | Nginx + Keepalived | 成熟稳定 |
| 存储（A） | 阿里云 NAS（RWX） | Pod 重建不丢数据 |
| 存储（B） | 本地 SSD + NFS/rsync 同步到备机 | 性能优先 |
| 认证 | LDAP（AD 也走 LDAP 协议） | 接公司目录 |
| 授权 | Role-based Authorization Strategy | 基于 LDAP group |
| 配置 | JCasC + Job DSL | YAML 入 Git |
| 密钥 | Jenkins Credentials + Vault 插件 | 二级保护 |
| 动态 Agent（A） | Kubernetes plugin | Pod 模板 |
| 静态 Agent（B） | SSH Build Agents 插件 | inbound JNLP 也支持 |
| 监控 | Prometheus 插件 + Grafana | metrics endpoint |
| 日志 | Filebeat → Loki/ELK | 集中查询 |
| 备份 | restic + 对象存储 | 增量、加密 |
| 备份内容 | `$JENKINS_HOME` 全量（排除 `workspace/`、`caches/`） | 关键是 `jobs/`、`users/`、`secrets/`、`credentials.xml` |

## 3. 是否需要外置数据库？

**结论：Jenkins 核心不需要外置 DB，绝大多数场景文件存储就够。** 以下情况才需要：

| 场景 | 是否需要外置 DB | 推荐方案 |
|---|---|---|
| 默认部署（构建/任务/用户/凭据） | **否** | 全部在 `$JENKINS_HOME` 文件存储 |
| 长期审计日志、合规要求 | 推荐 | Audit Trail 插件 → 写入 ELK / RDS PostgreSQL |
| 大规模历史构建检索（百万级） | 推荐 | 外置 ELK/OpenSearch 索引构建数据 |
| 用户自定义 Dashboard / BI | 视情况 | Grafana + 外置 Postgres |
| 插件依赖（Database / PostgreSQL plugin） | 看插件 | 外置 RDS PostgreSQL |
| `jk` 服务端聚合层（如做多控制器聚合视图） | 是 | 外置 Postgres，仅放聚合元数据 |

设计原则：
1. **`jenkins_home` 是事实唯一真相**，外置 DB 只做"分析/审计/聚合"二级用途，不替代主存储。
2. 上 RDS 时，强烈建议放在与 Jenkins 同 VPC，启用备份与多可用区。
3. 外置 DB 不存任何凭据明文（凭据仍走 Vault + Jenkins Credentials）。

> 如果你后续要做"多 Jenkins 集群统一视图""跨控制器聚合查询"，那 **聚合服务**（不是 Jenkins 本身）会需要一个外置 Postgres / ClickHouse。详见第 8 节"`jk` 服务端扩展（可选）"。

## 4. 用户视角："我的任务"如何呈现

### 4.1 Jenkins 原生能力

Jenkins 已内置以下机制，让登录用户聚焦自己的任务：

1. **People → 用户主页**：列出该用户**触发过**或**关联**的所有构建（`/user/<id>/builds`）。
2. **Build History 全局视图**：可按 Filter By Status / Cause 筛选 "Started by me"。
3. **My Views**：每个用户可创建私有视图，过滤自己关心的 job（如按文件夹、按正则、按标签）。
4. **Pipeline Stage View / Blue Ocean**：登录后默认聚焦自己最近的运行。
5. **通知**：邮件、Slack、企业微信、钉钉插件，把"自己的构建结果"主动推给本人。

### 4.2 通过 RBAC 让"看到的就是自己的"

权限模型决定了"用户能看到什么"。我们采用 **Folder + Role Strategy** 双层：

- 顶层文件夹 = 团队/产品（如 `team-payments/`、`team-search/`）。
- 文件夹角色：`folder-developer` / `folder-release` / `folder-viewer`，授权给对应 LDAP 组。
- 全局角色：`overall-read` 给 `cn=all-staff`（仅能看登录页与全局列表）；`admin` 给 `cn=ci-admins`。
- 个人 Job（用户自己的实验性 job）放在 `users/<userid>/` 文件夹下，仅本人可见 + 管理员只读。

效果：

- 普通开发：登录 → 看到自己团队 + 自己个人文件夹下的 job。
- Release 工程师：额外看到生产 job。
- Admin：全局可见。

### 4.3 `jk` CLI 的"我的任务"体验

`jk` 客户端可以直接利用 Jenkins API 实现 "my view"：

```bash
# 我作为触发者的最近构建
jk run ls --triggered-by $USER --since 7d --json

# 我有权限的所有 job
jk job ls --mine --json

# 给"我"建一个个人 dashboard 文件夹（首次登录引导）
jk folder ensure users/$USER --owner $USER
```

> 这部分能力部分已在 `jk` 中实现（参见 [`docs/spec.md`](../spec.md)、[`docs/api.md`](../api.md)），未实现的可按需补 issue。

## 5. 高可用与容灾

| 项 | 方案 A（ACK） | 方案 B（IDC） |
|---|---|---|
| 控制器副本 | StatefulSet replicas=1（K8s 自动重拉） | 主+冷备 VM，Keepalived VIP |
| 存储 | NAS 多可用区（按订购规格） | RAID10 + 每日 NFS/rsync 同步到备机 |
| 备份 | OSS 跨区域复制，保留 30 天 | restic → MinIO，保留 30 天，月度异地 |
| RTO | ≤ 15 min | ≤ 30 min |
| RPO | ≤ 1 h（可缩短至 15 min） | ≤ 24 h（可缩短至 1 h） |
| 演练 | 每季度一次"删 namespace 重建" | 每季度一次"备机接管" |

## 6. 认证与授权设计（LDAP）

**LDAP 接入参数**（向公司目录管理员索取，并填入 [`intake-template.yaml`](/assets/jenkins/intake-template.yaml)）：

- LDAP Server URL：`ldaps://ldap.corp.example.com:636`（强烈建议 ldaps）
- Root DN：`dc=corp,dc=example,dc=com`
- User search base：`ou=Users,dc=corp,dc=example,dc=com`
- User search filter：`sAMAccountName={0}`（AD）或 `uid={0}`（OpenLDAP）
- Group search base：`ou=Groups,dc=corp,dc=example,dc=com`
- Group membership filter：`member={0}`
- Manager DN：例 `cn=jenkins-bind,ou=ServiceAccounts,...`
- Manager Password：放进 Jenkins Credentials / Vault，**不写死 YAML**

**授权矩阵（Role Strategy）**

| 角色 | LDAP 组 | 权限范围 |
|---|---|---|
| `admin` | `cn=ci-admins` | 全权限 |
| `developer` | `cn=ci-developers` | 自己团队 Folder Read/Build/Cancel/Workspace |
| `release` | `cn=ci-release` | 生产 Folder 触发 + 凭据使用 |
| `viewer` | `cn=all-staff` | 全只读（含日志、artifact） |
| 匿名 | — | 拒绝（关闭匿名） |

文件夹级权限用 **Folder-based Authorization**：每个产品/团队一个 Folder，组授权到 Folder。

## 7. 网络与安全

- 控制器**不开公网**；公网访问统一走 SLB + 白名单 / 零信任网关。
- **仅放行**：443 (HTTPS), 50000 (JNLP，仅内网/agent 网段)。
- Jenkins 系统配置：
  - 启用 CSRF、启用 Agent → Master Access Control。
  - 禁用 CLI over remoting，仅保留 SSH/HTTP CLI（`jk` 用 REST）。
  - "Jenkins URL" 必须设置成 `https://jenkins.corp.example.com`。
- Pod/Agent 隔离：动态 agent 用独立 namespace + NetworkPolicy。
- 镜像来源：所有 builder 镜像走内部 ACR/Harbor，扫描通过才允许。
- Audit Trail 插件：日志归档 ≥ 180 天。

## 8. `jk` 客户端分发设计

- 二进制托管：内部 Nexus raw repo / OSS Bucket / 内部 Homebrew tap。
- 版本：跟随上游 Release，内部冒烟通过后推 stable。
- 工程师初始化：

  ```bash
  jk auth login --server https://jenkins.corp.example.com \
                --user $USER --token <从 Jenkins UI 生成>
  jk context list
  ```

- 多环境：`jk context add prod ...`、`jk context add staging ...`，CI 脚本里 `JK_CONTEXT=prod`。
- 机器人账号：在 Jenkins 建 `bot-ci` 用户，token 存 Vault，CI runner 启动时注入 `JK_TOKEN`。
- **强制 TLS**：分发文档里写明必须用 https URL；不接受裸 IP/HTTP。

### 8.1 `jk` 服务端扩展（可选，未来路线）

如果未来要做"跨多控制器统一视图""统计大盘""我的任务全局聚合"，可以加一层 **`jk-server`**：

```
┌────────┐   ┌──────────────┐   ┌──────────┐
│ jk CLI │──▶│  jk-server   │──▶│ Jenkins A│
└────────┘   │ (Go, REST)   │──▶│ Jenkins B│
             │ + Postgres   │   └──────────┘
             └──────────────┘
```

只有这个聚合层才需要外置 DB（Postgres / ClickHouse），Jenkins 控制器本身仍维持文件存储。

## 9. 备份与恢复

- 工具：`restic`（增量、加密、去重）。
- 内容：`$JENKINS_HOME` 排除 `workspace/`、`caches/`、`tmp/`、`*.log`。
- 频率：方案 A 每小时增量；方案 B 每日全量 + 每小时 jobs 目录增量。
- 保留：日 14、周 8、月 12，月度副本异地。
- 加密：restic repo password + 对象存储 SSE。
- **每季度演练**：拉一台干净机器，从备份还原，启动后冒烟测试。

## 10. 升级与变更管理

- 控制器：每月跟 LTS minor，先在 staging 控制器跑 7 天。
- 插件：每两周一次集中升级窗口；高危 CVE 走紧急流程。
- 变更全部走 Git PR（JCasC、Jobfile、Helm values），CI 自动校验 YAML schema。
- 变更窗口：周六 22:00-24:00 CST（按企业策略调整）。
