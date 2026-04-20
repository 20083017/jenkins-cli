# Operations Guide

This guide explains how to install dependencies, bootstrap C++ quality controls, and operate the Jenkins-based delivery path introduced in the platform plan.

## 1. Installation Strategy

### Workstation / Build-Agent Dependencies

Use `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-platform-deps.sh` to install the baseline CLI and C++ quality tooling:

```bash
/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-platform-deps.sh --mode quality
/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-platform-deps.sh --mode platform
```

Modes:

- `quality` installs `clang-format`, `clang-tidy`, `cmake`, `ninja`, `jq`, and Git prerequisites.
- `platform` installs the quality set and prints the expected Kubernetes / release CLI additions when they should be baked from official vendor repositories.
- On Linux, prefer pre-baked agent images for `kubectl` and `helm` instead of ad-hoc package-manager installs.

### Jenkins Controller Plugin Strategy

Use `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-jenkins-plugins.sh` on the controller host or within the controller image build:

```bash
/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-jenkins-plugins.sh
```

Default plugin set covers:

- Kubernetes agents
- Configuration as Code
- Core pipeline support
- Credentials / credentials binding
- Warnings NG and JUnit publishing
- Prometheus metrics
- SSE gateway support

Run the plugin install during image bake or maintenance windows, then restart Jenkins in a controlled manner.

## 2. Repository Bootstrap Strategy for C++ Services

For each target C++ repository:

```bash
/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/bootstrap-cpp-quality.sh \
  --target-dir /path/to/cpp-service \
  --header-filter '.*'
```

This script:

- Creates `.clang-format` when missing.
- Creates `.clang-tidy` when missing.
- Creates `artifacts/cpp-quality/` for report output.
- Leaves existing policy files untouched unless `--force` is supplied.

After bootstrap, make sure the project build generates `compile_commands.json`. The preferred approach is:

```bash
cmake -S . -B build/ci -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

## 3. CI / Jenkins Operation Strategy

1. Run format checks before compilation to fail fast.
2. Generate `compile_commands.json` during configure.
3. Run `clang-tidy` against the same build directory used for compilation.
4. Archive reports and expose them to agents via Jenkins artifacts.
5. Keep release jobs dependent on quality gate success.

Recommended shared-library wrapper order:

1. `toolBootstrap`
2. `checkout`
3. `cppQualityGate`
4. `build`
5. `test`
6. `imagePublish`
7. `deploy`

## 4. Day-2 Operations Strategy

### Toolchain Maintenance

- Pin exact versions of `clang-format` and `clang-tidy` in agent images.
- Upgrade toolchains in a staging controller first.
- Rebaseline `clang-tidy` only during planned maintenance windows.

### Jenkins Maintenance

- Keep plugin lists in version control.
- Roll plugin updates through dev → staging → prod controllers.
- Backup JCasC, credential references, and Jenkins home before upgrades.

### Rollout Operations

- Pause rollout automatically when SLO alerts or readiness checks degrade.
- Use `jk run view --follow` for release job visibility.
- Route rollback requests through a dedicated rollback job with auditable parameters.

## 5. Verification Commands

Local or agent-side verification:

```bash
clang-format --version
clang-tidy --version
cmake --version
jk --version
kubectl version --client
helm version
```

Pipeline-side verification:

```bash
/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/check-cpp-quality.sh \
  --source-dir /path/to/cpp-service \
  --build-dir /path/to/cpp-service/build/ci
```

## 6. Troubleshooting

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| `clang-tidy` cannot find headers | Missing or stale `compile_commands.json` | Re-run CMake configure with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` |
| Format stage reports no files | Source glob does not match repository layout | Pass `--files` explicitly or adapt directory layout |
| Jenkins agents miss tools | Base image drift | Re-run dependency install during image build and verify PATH |
| Plugin install fails | `jenkins-plugin-cli` missing or controller offline | Install CLI in image or run during maintenance window |
| Agents cannot summarize reports | Artifacts were not archived | Ensure `archiveArtifacts` includes `artifacts/cpp-quality/**/*` |
