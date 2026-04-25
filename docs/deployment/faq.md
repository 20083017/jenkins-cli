# 常见问题（FAQ）

## Q1. 公司内部能用 IP 代替域名吗？

**能用，但强烈建议域名（哪怕是内部域名）**。详细对比：

| 维度 | 用 IP | 用域名（推荐） |
|---|---|---|
| HTTPS 证书 | 需自签 IP SAN 证书，浏览器/curl/`jk` 都要手动信任 | 内部 CA 或 ACME 可签，统一信任链 |
| 反向代理 / Ingress | Nginx Ingress、K8s Service 通常依赖 Host header | 原生支持 |
| 迁移 / 扩容 | 控制器换机器要改所有客户端配置 | 改 DNS A 记录即可 |
| Jenkins URL | "Jenkins URL" 配成 IP 后 webhook、邮件、Blue Ocean 链接全部写死 | 平滑 |
| LDAP / SSO 回调 | 部分 IdP 校验 host，IP 经常被拒 | 兼容性好 |
| 审计、合规 | IP 没语义，难追溯 | 命名清晰 |

**最低成本方案**：在公司 DNS（CoreDNS / AD DNS / 路由器）加一条 A 记录：

- `jenkins.corp.example.com → 10.10.20.5`
- `jenkins.idc.local → 10.0.1.10`（连内部域名都没有就用 `.local` / `.lan`）

如果完全没有 DNS 控制权，临时：

- `/etc/hosts` 写死（仅 PoC）。
- 或起一个 dnsmasq 容器作为内部 DNS。

证书方面：内部建议搭一个 [smallstep `step-ca`](https://smallstep.com/docs/step-ca/) 半小时即可；
或用 Let's Encrypt **DNS-01 challenge**，即使域名不对外解析也能签证书（只要能控制 DNS TXT）。

---

## Q2. 是否一定需要外置数据库？

**不一定。Jenkins 核心使用 `$JENKINS_HOME` 文件存储，多数场景不需要外置 DB**。

什么时候才考虑外置 DB：

| 场景 | 是否需要 | 推荐方案 |
|---|---|---|
| 默认部署（构建/任务/用户/凭据） | **不需要** | 全部在 `$JENKINS_HOME` 下文件存储 |
| 长期审计日志、合规要求 | 推荐 | Audit Trail 插件 → ELK / 外置 PostgreSQL |
| 大规模历史构建检索（百万级） | 推荐 | 外置 ELK / OpenSearch 索引 |
| 用户自定义 Dashboard / BI | 视情况 | Grafana + 外置 Postgres |
| 某些插件依赖（如 Database 插件） | 看插件 | 外置 RDS PostgreSQL |
| `jk` 服务端聚合多控制器 | 是 | 外置 Postgres / ClickHouse 仅放聚合元数据 |

设计原则：

1. `jenkins_home` 是事实唯一真相；外置 DB 只做"分析/审计/聚合"二级用途。
2. 外置 DB **不存任何凭据明文**，凭据仍走 Vault + Jenkins Credentials。
3. 上 RDS 时，与 Jenkins 同 VPC，启用自动备份与多可用区。

> 简而言之：**起步阶段不要外置 DB，复杂了再加**。先把备份做扎实，比上 DB 更重要。

---

## Q3. 用户登录后能不能直接看到"自己的所有任务"？

**可以，组合使用以下机制即可**：

### 3.1 Jenkins 原生

1. **People → 用户主页** `/user/<id>/builds`：列出该用户**触发过**或**关联**的最近构建。
2. **Build History 全局视图**：可按 "Started by me" 过滤。
3. **My Views**：每个用户可创建私有视图（按 Folder / 正则 / 标签过滤）。
4. **Pipeline Stage View / Blue Ocean**：登录后默认聚焦自己最近的运行。
5. **通知**：邮件 / Slack / 企业微信 / 钉钉，把自己的构建结果主动推给本人。

### 3.2 RBAC 让"看到的就是自己的"

我们采用 **Folder + Role Strategy** 双层：

- 顶层文件夹 = 团队 / 产品（如 `team-payments/`、`team-search/`）。
- 文件夹角色：`folder-developer` / `folder-release` / `folder-viewer`，授权给对应 LDAP 组。
- 全局角色：`overall-read` 给 `cn=all-staff`；`admin` 给 `cn=ci-admins`。
- 个人沙箱：`users/<userid>/` 文件夹，仅本人可见 + 管理员只读。

效果：

- 普通开发：登录后看到自己团队 + 个人沙箱的 job。
- Release 工程师：额外看到生产 job。
- Admin：全局可见。

### 3.3 `jk` CLI 视角

```bash
# 我作为触发者的最近构建
jk run ls --triggered-by $USER --since 7d --json

# 我有权限看到的所有 job
jk job ls --mine --json

# 关注的多个 job 在一个面板里看
jk run ls --job-glob 'team-payments/*' --filter result=FAILURE --since 24h
```

> 个别选项（如 `--mine`、`--triggered-by`）若当前版本未实现，可以提 issue / 通过 `--filter` 配合 `cause.userId=...` 实现等价效果。

---

## Q4. 一定要用 K8s 吗？小团队不想搞 K8s 怎么办？

不必。**< 50 人团队**完全可以用 [`deploy-idc-lan.md`](./deploy-idc-lan.md) 的"单 VM + Docker Compose + 静态 agent"方案，运维成本最低，恢复也最简单（拷贝 `jenkins_home` + 起容器即可）。

**> 50 人或并发构建 ≥ 30** 时，K8s 的弹性 Pod agent 优势开始显著，再迁移到 [`deploy-aliyun-ack.md`](./deploy-aliyun-ack.md)。

---

## Q5. Jenkins 能做真正的双活 HA 吗？

**OSS Jenkins 不支持 active-active**。controller 是有状态、单实例的设计。可选：

- **冷备**（本文采用）：备机持续同步 `jenkins_home`，故障时切 VIP，分钟级 RTO。
- **CloudBees CI**（商业）：支持 controller 集群 + Operations Center。
- **拆分小集群**：按团队/产品拆多个独立 controller，降低单点爆炸半径。
