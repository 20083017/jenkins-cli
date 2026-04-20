# C++ Static Analysis Pipeline Template

This template assumes Jenkins declarative pipelines, a CMake-based project, and the helper scripts shipped in `/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform`.

## Jenkinsfile Template

```groovy
pipeline {
  agent { label 'linux && cpp' }

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  environment {
    BUILD_DIR = 'build/ci'
    CMAKE_GENERATOR = 'Ninja'
    CMAKE_BUILD_TYPE = 'RelWithDebInfo'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Bootstrap Tooling') {
      steps {
        sh '/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/install-platform-deps.sh --mode quality'
      }
    }

    stage('Bootstrap Policy Files') {
      steps {
        sh '/home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/bootstrap-cpp-quality.sh --target-dir "$WORKSPACE" --header-filter ".*"'
      }
    }

    stage('Format and Static Analysis') {
      steps {
        sh '''
          /home/runner/work/jenkins-cli/jenkins-cli/scripts/platform/check-cpp-quality.sh \
            --source-dir "$WORKSPACE" \
            --build-dir "$WORKSPACE/${BUILD_DIR}" \
            --cmake-generator "$CMAKE_GENERATOR" \
            --cmake-build-type "$CMAKE_BUILD_TYPE"
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'artifacts/cpp-quality/**/*', allowEmptyArchive: true
        }
      }
    }

    stage('Build') {
      steps {
        sh 'cmake -S . -B "$BUILD_DIR" -G "$CMAKE_GENERATOR" -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON'
        sh 'cmake --build "$BUILD_DIR" --parallel'
      }
    }

    stage('Unit Test') {
      steps {
        sh 'ctest --test-dir "$BUILD_DIR" --output-on-failure'
      }
      post {
        always {
          junit testResults: 'artifacts/test-results/**/*.xml', allowEmptyResults: true
        }
      }
    }
  }
}
```

## Expected Repository Inputs

- `CMakeLists.txt` or equivalent build entrypoint.
- A committed `.clang-format` and `.clang-tidy`, or permission for the bootstrap script to create them.
- Build agents with a compiler toolchain compatible with the target standard library and ABI.
- Prefer baking the required tooling into the Jenkins agent image; keep the bootstrap stage only as an idempotent safety net.

## Recommended Artifact Layout

The helper script writes reports under `artifacts/cpp-quality/`:

- `format-report.txt`
- `tidy-report.txt`
- `formatted-files.txt`
- `compile-commands-path.txt`

Publish these artifacts for pull-request feedback and agent summarization.

## Shared Library Integration Notes

If Jenkins Shared Library wrappers are used, centralize these concerns:

1. Tool installation and version pinning.
2. Report archiving and retention policy.
3. Baseline comparison for `clang-tidy` findings.
4. Notification payloads to chat, email, or incident tooling.
5. Build image selection per compiler family.

## Failure Handling

- Fail immediately on format drift.
- Fail immediately on new high-severity `clang-tidy` findings.
- Allow nightly informational jobs to run with `ALLOW_TIDY_WARNINGS=1` only outside protected branches.
- Require human approval before overriding a broken quality gate on a release branch.
