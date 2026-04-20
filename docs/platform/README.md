# Platform Delivery Assets

This folder captures the delivery assets for the Kubernetes + Jenkins + agent rollout plan discussed for this repository workspace.

## Documents

- [Implementation Checklist](implementation-checklist.md) — phased execution checklist from environment bootstrap through handover.
- [Quality Gate Policy](quality-gate-policy.md) — gate definitions, severity policy, block rules, and evidence requirements.
- [C++ Static Analysis Pipeline Template](cpp-static-analysis-pipeline.md) — Jenkins pipeline template for `clang-format` and `clang-tidy`.
- [Skills / Agent Responsibility Matrix](skills-agent-responsibility-matrix.md) — capability ownership, inputs, outputs, and approval boundaries.
- [Operations Guide](operations-guide.md) — installation, deployment, configuration, and day-2 operations guidance.

## Scripts

- `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-platform-deps.sh`
- `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/bootstrap-cpp-quality.sh`
- `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/check-cpp-quality.sh`
- `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-jenkins-plugins.sh`

These scripts are idempotent templates intended to be adapted for the target Jenkins controller, Kubernetes cluster, and C++ repository before execution in production.
