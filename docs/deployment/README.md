# Jenkins + `jk` 平台部署文档

本目录是一份完整的 **Jenkins 控制器 + `jk` 客户端** 落地参考，目标读者：

- 平台 / SRE 工程师：负责搭建与运维。
- 应用开发者：通过 `jk` CLI 与 Web UI 使用 Jenkins。
- 安全 / 合规：审计访问、密钥、备份、补丁。

## 文档地图

| 文件 | 用途 |
|---|---|
| [`proxy-and-lb-primer.md`](./proxy-and-lb-primer.md) | 5 分钟入门：VIP / L4 LB / L7 反向代理（含 Nginx 原理速记） |
| [`topology.md`](./topology.md) | 拓扑文档（通用逻辑拓扑、阿里云 ACK、本地 IDC） |
| [`design.md`](./design.md) | 设计文档（HA / 权限 / 备份 / 网络 / 合规 / LDAP） |
| [`deploy-aliyun-ack.md`](./deploy-aliyun-ack.md) | 阿里云 ACK（K8s）部署手册 |
| [`deploy-idc-lan.md`](./deploy-idc-lan.md) | 本地 IDC 局域网（VM + Docker Compose）部署手册 |
| [`checklist.md`](./checklist.md) | 上线 / 安全 / 合规 检查清单 |
| [`intake-template.yaml`](./intake-template.yaml) | 需要用户/平台方提供的信息模板 |
| [`faq.md`](./faq.md) | 常见问题：域名 vs IP、是否需要外置 DB、用户能看自己的任务吗 |

## 快速决策

- **中大型团队、已有 K8s** → 用 [阿里云 ACK 方案](./deploy-aliyun-ack.md)。
- **小团队、传统机房、无 K8s 经验** → 用 [本地 IDC 方案](./deploy-idc-lan.md)。
- **PoC / 临时环境** → 直接 IDC 单 VM + Docker Compose 起步，后续再迁移。

> 落地前请先填好 [`intake-template.yaml`](./intake-template.yaml) 中的字段，避免反复返工。
