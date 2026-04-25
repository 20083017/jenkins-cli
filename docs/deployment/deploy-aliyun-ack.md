# 部署手册：阿里云 ACK（Kubernetes）

适用于中大型团队，已具备阿里云 ACK 集群与基础运维能力。

## 1. 前置准备

- 已购买并初始化 ACK 标准版集群（≥3 worker，每节点 4C8G 起步）。
- 已开通：
  - **NAS**（RWX 文件系统，给 `jenkins_home`）
  - **OSS**（备份桶）
  - **ACR**（镜像仓库）
  - **SLB**（ALB / NLB）
- 内部 DNS 已配置 `jenkins.corp.example.com → ACK Ingress 入口 IP`。
- LDAP/AD 信息齐备（见 [design.md §6](./design.md)）。
- 本机已配置：`kubectl`、`helm 3.12+`、`阿里云 CLI`（可选）。

## 2. 步骤

### 2.1 创建 namespace 与基础 Secret

```bash
kubectl create namespace jenkins
kubectl -n jenkins create secret generic ldap-bind \
  --from-literal=managerDN='cn=jenkins-bind,ou=ServiceAccounts,dc=corp,dc=example,dc=com' \
  --from-literal=managerPassword='REDACTED'
```

### 2.2 准备 PVC（绑定 NAS）

如果集群已自带阿里云 NAS CSI，则只需建 PVC；否则先按官方文档安装 `csi-plugin`。

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-home-pvc
  namespace: jenkins
spec:
  accessModes: [ReadWriteMany]
  storageClassName: alibabacloud-cnfs-nas
  resources:
    requests:
      storage: 50Gi
```

```bash
kubectl apply -f pvc.yaml
```

### 2.3 安装 cert-manager（如未装）

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set installCRDs=true
```

为内部 CA 或 Let's Encrypt DNS-01（阿里云 DNS provider）配置 ClusterIssuer：

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    email: ops@corp.example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-dns-account
    solvers:
      - dns01:
          webhook:
            groupName: cert-manager.alidns.com
            solverName: alidns-solver
            config:
              accessKeyIdRef: { name: alidns-secret, key: accessKey }
              accessKeySecretRef: { name: alidns-secret, key: secretKey }
```

### 2.4 编写 `values.yaml`

关键片段（节选；完整请按官方 chart 文档补全）：

```yaml
controller:
  image:
    tag: lts-jdk21
  jenkinsUrl: https://jenkins.corp.example.com
  installPlugins:
    - configuration-as-code
    - kubernetes
    - ldap
    - role-strategy
    - prometheus
    - workflow-aggregator
    - git
    - pipeline-utility-steps
    - audit-trail
    - hashicorp-vault-plugin
    - job-dsl
    - matrix-auth
    - blueocean
  persistence:
    existingClaim: jenkins-home-pvc
  ingress:
    enabled: true
    ingressClassName: nginx
    hostName: jenkins.corp.example.com
    tls:
      - secretName: jenkins-tls
        hosts: [jenkins.corp.example.com]
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-dns
  JCasC:
    defaultConfig: true
    configScripts:
      jenkins-base: |
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
                  groupMembershipStrategy:
                    fromGroupSearch:
                      filter: "member={0}"
                  managerDN: "${LDAP_MANAGER_DN}"
                  managerPasswordSecret: "${LDAP_MANAGER_PASSWORD}"
        unclassified:
          location:
            url: https://jenkins.corp.example.com
            adminAddress: ops@corp.example.com
agent:
  enabled: true
  podTemplates:
    java: |
      - name: java
        label: linux && java
        containers:
          - name: jnlp
            image: jenkins/inbound-agent:latest
          - name: maven
            image: cr.cn-hangzhou.aliyuncs.com/devops/maven:3.9-jdk21
            command: ["sleep"]
            args: ["999d"]
serviceAccount:
  create: true
```

将 LDAP secret 通过 envFrom 注入：

```yaml
controller:
  containerEnvFrom:
    - secretRef:
        name: ldap-bind
```

### 2.5 安装

```bash
helm repo add jenkins https://charts.jenkins.io
helm upgrade --install jenkins jenkins/jenkins -n jenkins -f values.yaml
```

等待就绪：

```bash
kubectl -n jenkins rollout status sts/jenkins
kubectl -n jenkins get pods,svc,ingress
```

### 2.6 首次验证

```bash
curl -I https://jenkins.corp.example.com/login
# 期望 200 / 403（取决于匿名策略）
```

浏览器打开 `https://jenkins.corp.example.com`，使用 LDAP 账号登录。

### 2.7 接入 Webhook、Vault、监控、备份

- **Webhook**：GitLab/Bitbucket → Jenkins URL `/multibranch-webhook-trigger/...` 或插件提供的 endpoint。
- **Vault**：系统配置 → Vault URL + AppRole；Pipeline 用 `withVault {}`。
- **监控**：Prometheus Operator 加 ServiceMonitor 抓 `/prometheus`，导入 Grafana Dashboard ID 9964。
- **备份**：

```yaml
# backup-cronjob.yaml（节选）
apiVersion: batch/v1
kind: CronJob
metadata: { name: jenkins-backup, namespace: jenkins }
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: restic
              image: restic/restic:latest
              env:
                - name: RESTIC_REPOSITORY
                  value: "s3:https://oss-cn-hangzhou-internal.aliyuncs.com/company-jenkins-backup"
                - name: RESTIC_PASSWORD
                  valueFrom: { secretKeyRef: { name: restic-secret, key: password } }
                - name: AWS_ACCESS_KEY_ID
                  valueFrom: { secretKeyRef: { name: oss-secret, key: ak } }
                - name: AWS_SECRET_ACCESS_KEY
                  valueFrom: { secretKeyRef: { name: oss-secret, key: sk } }
              command: ["sh","-c"]
              args:
                - |
                  restic backup /jenkins_home --exclude='workspace/*' --exclude='caches/*' && \
                  restic forget --keep-daily 14 --keep-weekly 8 --prune
              volumeMounts:
                - { name: home, mountPath: /jenkins_home, readOnly: true }
          volumes:
            - name: home
              persistentVolumeClaim: { claimName: jenkins-home-pvc }
```

### 2.8 `jk` 客户端验证

```bash
jk auth login --server https://jenkins.corp.example.com --user $USER --token <PAT>
jk context list
jk job ls
jk run ls --since 24h
```

## 3. 升级 / 回滚

```bash
# 升级（先在 staging 验证）
helm upgrade jenkins jenkins/jenkins -n jenkins -f values.yaml

# 回滚
helm rollback jenkins -n jenkins
```

## 4. 灾难恢复演练（每季度）

1. 创建一个 `jenkins-dr` namespace。
2. 用最新备份在临时 PVC 中 `restic restore`。
3. Helm install 同样的 chart，挂临时 PVC。
4. 校验 LDAP 登录、关键 job 列表、最近一次构建可重跑。
5. 销毁该 namespace。
