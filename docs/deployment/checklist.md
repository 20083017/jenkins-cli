# 检查清单

## 1. 通用上线 Checklist

- [ ] DNS 记录可解析（内外网均测试）
- [ ] HTTPS 证书有效，浏览器、curl、`jk` 都信任
- [ ] Jenkins URL 在系统配置中正确
- [ ] 关闭匿名访问、关闭 Setup Wizard
- [ ] LDAP 登录成功；至少 3 个测试用户：admin / dev / viewer
- [ ] Role Strategy 矩阵生效（dev 看不到生产 job，viewer 不能 build）
- [ ] CSRF 启用、Agent → Master Access Control 启用
- [ ] CLI over remoting 已禁用
- [ ] Webhook 触发成功（push、MR/PR）
- [ ] 至少跑通一个 Hello World Pipeline + 一个 Multibranch Pipeline
- [ ] 一个动态 agent + 一个静态 agent 都能正常构建
- [ ] Artifact 上传/下载、Test 报告解析正常
- [ ] Prometheus 指标可见，Grafana 面板出图
- [ ] 日志进入集中平台（Loki/ELK），可按 build 检索
- [ ] 备份任务运行，`restic snapshots` 有记录
- [ ] **执行一次完整恢复演练**（从备份还原到一台干净机器）
- [ ] Vault 集成：一个 Job 用 `withVault` 拿到测试密钥
- [ ] `jk auth login` + `jk run ls` + `jk run trigger` + `jk run watch` 全部通过
- [ ] 用户登录后能看到 "我的任务"（个人主页 + My Views + `jk run ls --triggered-by $USER`）
- [ ] 安全扫描：Trivy 镜像、`nikto`/Burp 简扫 Web
- [ ] 文档：`docs/runbook.md` 包含告警处置、备份恢复、版本升级 SOP
- [ ] 应急联系人 / 值班表已就位

## 2. 方案 A（阿里云 ACK）专属

- [ ] NAS 性能 PVC 实测 IOPS/吞吐达标（建议 ≥ 100 MB/s）
- [ ] cert-manager 自动续期成功（手动触发一次）
- [ ] ACK 节点污点 / 容忍度配置正确，controller 不会被驱逐
- [ ] 动态 agent Pod 能成功拉取 ACR 镜像（imagePullSecret 已配）
- [ ] NetworkPolicy：agent namespace 只能访问必要外部
- [ ] PodDisruptionBudget 设置（controller minAvailable=1）
- [ ] 跨 AZ 调度策略生效
- [ ] OSS 备份桶版本控制 + 跨区复制开启

## 3. 方案 B（IDC）专属

- [ ] Keepalived VIP 主备切换 < 5s
- [ ] Nginx 配置 `proxy_buffering off`、超时 ≥ 300s（长任务日志流）
- [ ] 主备 `jenkins_home` rsync 一致性校验
- [ ] 防火墙只放行 443 / 50000 / 22
- [ ] 物理机 BIOS 时间同步（NTP），否则 LDAP/Kerberos 易失败
- [ ] 磁盘 SMART 监控、RAID 状态监控接入告警
- [ ] UPS / 机房断电演练
- [ ] MinIO 备份桶 versioning + 异地副本

## 4. 安全合规 Checklist

- [ ] 所有密钥不在 Git、不在 JCasC YAML 明文（占位符 + Vault / env）
- [ ] Audit Trail 插件开启，日志保留 ≥ 180 天
- [ ] 禁止使用 root agent；构建容器 `runAsNonRoot`
- [ ] 镜像扫描通过（Trivy / CNNVD）
- [ ] 插件升级策略：staging 控制器先验证 7 天
- [ ] 漏洞响应 SLA：高危 ≤ 7 天，中危 ≤ 30 天
- [ ] 数据分类：构建产物保留期、日志保留期文档化
- [ ] 访问审计：每季度复核 LDAP 组成员
- [ ] 备份加密 + 异地副本
- [ ] 控制器无公网直连；外部访问走 SLB 白名单或零信任网关

## 5. 用户体验 Checklist（"我的任务"）

- [ ] 登录用户首页能看到 People / Build History 入口
- [ ] `/user/<id>/builds` 能列出本人触发的最近构建
- [ ] My Views 可创建并保存
- [ ] `jk run ls --triggered-by $USER` 工作正常
- [ ] 失败构建邮件 / IM 推送到本人
- [ ] 个人沙箱文件夹 `users/<userid>/` 存在且仅本人可见
