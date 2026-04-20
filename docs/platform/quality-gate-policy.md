# Quality Gate Policy

The table below defines the minimum release gates for repositories that participate in the Kubernetes + Jenkins delivery platform.

| Stage | Gate | Tool / Source | Default Trigger | Pass Criteria | Block Behavior | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| Source hygiene | Formatting | `clang-format --dry-run --Werror` | Every pull request and mainline build | No formatting drift in tracked C/C++ sources or headers | Block merge and release stages | Console log + formatted file list artifact |
| Static analysis | C++ semantic checks | `clang-tidy` with project `.clang-tidy` + `compile_commands.json` | Every pull request and mainline build | No new high-severity issues; medium issues allowed only when accepted into baseline | Block merge and release stages | SARIF or text report artifact |
| Build validity | Native build | `cmake --build` / project build command | Every pull request and release build | Build completes with configured warnings policy | Block downstream test, package, and deploy stages | Build log |
| Unit quality | Unit tests | Repository unit test command | Every pull request and release build | All mandatory suites pass; flaky tests must be quarantined separately | Block package and deploy stages | JUnit or native test report |
| Security | Dependency / image scanning | `trivy`, repository-approved scanner | Release branches and image build jobs | No unresolved critical findings; high findings require explicit waiver | Block image publish and deploy stages | Scan report artifact |
| Application quality | Code rules | SonarQube / Semgrep / approved scanners | Pull request and nightly baseline jobs | Quality profile passes; no new blocker issues | Block merge on protected branches | Scanner report link |
| Deployment readiness | Rollout pre-checks | Jenkins + Argo Rollouts + readiness probes | Pre-deploy and progressive rollout steps | Latest build passed all upstream gates and environment health is green | Pause or abort rollout | Rollout event log |

## C++ Severity Policy

| Severity | Examples | Default Policy | Exception Path |
| --- | --- | --- | --- |
| Critical | Undefined behavior, memory safety, command injection, unsafe deserialization | Must be fixed before merge | None except security emergency break-glass with director approval |
| High | Resource leaks, null dereference, thread-safety defects, dangerous API misuse | Must be fixed before merge | Time-boxed waiver with owner and due date |
| Medium | Readability, maintainability, portability, performance smells | Track in backlog or baseline if pre-existing | Accepted baseline entry with review sign-off |
| Low | Style and informational findings | Fix opportunistically | No waiver required |

## Baseline and Waiver Rules

1. Existing `clang-tidy` findings may be recorded as a baseline only once, before the gate becomes mandatory.
2. Baselines must be stored in version control and reviewed alongside the rule configuration.
3. New findings that are not in the approved baseline fail the pipeline automatically.
4. `NOLINT` / `// clang-format off` usage must include a short reason and a ticket reference when used outside generated code.
5. Waivers must contain scope, owner, expiry date, and cleanup plan.

## Operational Defaults

- Preferred C++ build metadata source: `CMAKE_EXPORT_COMPILE_COMMANDS=ON`.
- Preferred formatting scope: tracked files under `src/`, `include/`, `lib/`, and `test/`.
- Preferred static-analysis scope: all `.c`, `.cc`, `.cpp`, `.cxx` sources built in CI.
- Pull request builds should fail fast on format drift before spending time on full compilation.
- Nightly jobs should run the full static analysis set and publish trendable artifacts.
