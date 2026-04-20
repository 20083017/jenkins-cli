# Skills / Agent Responsibility Matrix

| Role | Primary Scope | Typical Inputs | Typical Outputs | Automation Boundary | Required Approval |
| --- | --- | --- | --- | --- | --- |
| Jenkins Ops Agent | Jenkins controller health, plugin status, queue, node availability | `jk plugin ls`, `jk queue ls`, `jk node ls`, controller alerts | Incident summary, plugin drift report, remediation commands | Read-only by default; may execute approved maintenance scripts in lower environments | Production controller changes |
| Quality Gate Agent | Build quality evaluation, `clang-format`, `clang-tidy`, test and scan summaries | Jenkins build URL, archived reports, baseline files | Pass/fail decision, finding summary, top offending files | May annotate PRs and fail builds automatically | Baseline updates and waiver creation |
| Release Agent | Deployment orchestration and rollout status | Build metadata, image tag, rollout name, environment policy | Deploy request, rollout progress summary, rollback recommendation | May trigger non-production deploys and pause/resume rollouts | Production promotion |
| Observability Agent | Metrics, alerts, release health correlation | Prometheus alerts, Argo Rollouts status, Jenkins build metadata | Root-cause hints, health dashboards, SLO breach summary | Read-only automation; may page responders | Paging policy changes |
| Rollback Agent | Safe rollback execution and evidence collection | Rollout state, release inventory, approval token | Rollback plan, rollback audit bundle, post-rollback status | May prepare rollback payloads automatically | Production rollback execution |
| Platform Delivery Agent | Documentation, scripts, onboarding, policy enforcement | Platform standards, repository metadata, tool versions | Updated docs, installation scripts, rollout checklist | May update templates and runbooks in version control | Final approval on policy changes |

## Command Mapping with `jk`

| Role | Core `jk` Commands | Purpose |
| --- | --- | --- |
| Jenkins Ops Agent | `jk plugin ls`, `jk queue ls`, `jk node ls`, `jk log` | Inspect controller state and agent capacity |
| Quality Gate Agent | `jk run ls --with-meta`, `jk run view`, `jk artifact download`, `jk test report` | Pull build reports and summarize gate outcomes |
| Release Agent | `jk run start`, `jk run view --follow`, `jk artifact ls` | Trigger approved jobs and watch rollout workflows |
| Observability Agent | `jk run ls`, `jk log`, `jk artifact download` | Correlate build events with telemetry systems |
| Rollback Agent | `jk run ls`, `jk run start`, `jk run view --follow` | Prepare or execute rollback jobs |

## Approval and Safety Rules

1. Agents must use least-privilege Jenkins and Kubernetes identities.
2. Production deploys, rollback execution, plugin installs, and waiver approvals require named human approvers.
3. Agents may summarize secrets usage but must never echo secret values.
4. Agent decisions must be traceable to archived Jenkins artifacts, metrics snapshots, or committed policy files.
5. Every automated action must have a deterministic rollback or manual recovery path.
