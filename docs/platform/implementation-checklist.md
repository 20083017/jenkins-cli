# Implementation Checklist

Use this checklist to execute the Kubernetes + Jenkins delivery plan in controlled phases.

## Phase 1 — Foundation

- [ ] Confirm target environments, cluster names, Jenkins URLs, and ownership model.
- [ ] Freeze plugin baseline, Jenkins LTS version, Kubernetes version, and supported C++ toolchain versions.
- [ ] Prepare a dedicated Jenkins namespace, service accounts, registry credentials, and secret rotation process.
- [ ] Define storage classes and backup policy for Jenkins home, build caches, and quality reports.
- [ ] Decide the standard C++ build generator (`cmake` + `ninja` recommended) and how `compile_commands.json` will be produced.

## Phase 2 — Controller and Agent Bootstrap

- [ ] Install Jenkins controller dependencies with `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-jenkins-plugins.sh` or controller-image bake process.
- [ ] Apply JCasC baseline, RBAC policy, credentials, and shared library registration.
- [ ] Provision Kubernetes-based Jenkins agents with the required build image and workspace policy.
- [ ] Install operator dependencies on build agents with `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-platform-deps.sh`.
- [ ] Validate `jk`, `kubectl`, `helm`, `cmake`, `clang-format`, and `clang-tidy` availability in the agent image.

## Phase 3 — C++ Quality Gate Enablement

- [ ] Bootstrap `.clang-format` and `.clang-tidy` in each target C++ repository with `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/bootstrap-cpp-quality.sh`.
- [ ] Ensure CI can generate `compile_commands.json` for every supported C++ build flavor.
- [ ] Add `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/check-cpp-quality.sh` to the Jenkins shared library or repository-local pipeline.
- [ ] Publish format drift and static analysis reports as Jenkins artifacts.
- [ ] Define the exception process for temporary suppressions and baseline waivers.

## Phase 4 — Release Control and Observability

- [ ] Wire quality gate pass/fail signals into image build and deployment stages.
- [ ] Integrate Argo Rollouts or equivalent canary controller with Jenkins release jobs.
- [ ] Expose build, rollout, and service metrics to Prometheus.
- [ ] Configure Alertmanager routing for rollout degradation, high failure rate, and repeated quality regressions.
- [ ] Test pause, resume, abort, and rollback workflows with audit capture.

## Phase 5 — Skills / Agent Enablement

- [ ] Register the `jk` skill and any platform-specific skills in the target agent runtime.
- [ ] Map skill permissions to Jenkins RBAC, Kubernetes RBAC, and secret boundaries.
- [ ] Validate agent workflows for build inspection, release status, and rollback assistance.
- [ ] Teach agents to summarize `clang-format` and `clang-tidy` failures from archived reports.
- [ ] Add human approval gates for production deploys, rollback overrides, and policy exceptions.

## Phase 6 — Handover and Day-2 Readiness

- [ ] Run a controlled pilot with one representative C++ service.
- [ ] Capture SLOs for build duration, lint queue time, rollout success rate, and rollback MTTR.
- [ ] Finalize runbooks, escalation paths, and on-call ownership.
- [ ] Review plugin upgrades, toolchain upgrades, and security patch cadence.
- [ ] Freeze the release checklist and communicate the cutover plan.
