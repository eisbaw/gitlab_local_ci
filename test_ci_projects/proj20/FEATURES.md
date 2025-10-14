# Feature Mapping: proj1-proj19 → proj20

This document maps all features from individual test projects (proj1-proj19) to their implementation in the comprehensive proj20 kitchen sink example.

## Feature Source Mapping

| Project | Primary Feature | Implementation in proj20 |
|---------|----------------|---------------------------|
| **proj1** | Simple script execution | All jobs use script commands |
| **proj2** | Basic stages | 12-stage pipeline structure |
| **proj3** | Parallel jobs in same stage | Multiple test/build jobs run in parallel |
| **proj4** | Artifacts and dependencies | All build jobs produce artifacts consumed by test jobs |
| **proj5** | Extensive variables | Global variables + job-specific + dotenv artifacts |
| **proj6** | Artifacts with expiration | All artifacts have expire_in settings |
| **proj7** | Services (PostgreSQL, Redis, etc.) | Multiple jobs use services with aliases |
| **proj8** | Rules with conditionals | Branch rules, change rules, manual rules throughout |
| **proj9** | Cache configuration | Global cache + job-specific overrides with dynamic keys |
| **proj10** | Before/after scripts | Global hooks + job overrides + !reference usage |
| **proj11** | Include directives | Includes frontend.yml, backend.yml, security.yml, monitoring.yml |
| **proj12** | YAML anchors | Anchors for configs: base_config, docker_config, node_config, etc. |
| **proj13** | Extends keyword | Hidden templates (.base_job, .test_job, .deploy_job) |
| **proj14** | Retry and timeout | Jobs have retry with conditions + timeout + interruptible |
| **proj15** | Reports (JUnit, coverage) | All test jobs produce JUnit and coverage reports |
| **proj16** | Child pipeline triggers | trigger:monitoring-setup with strategy: depend |
| **proj17** | Matrix parallelization | test:matrix:compatibility with 3D matrix (SERVICE×ENV×RUNNER) |
| **proj18** | Resource groups | All staging/prod deployments use resource groups |
| **proj19** | [Not found] | - |

## Feature Categories

### Basic Pipeline Structure
- ✅ **Stages**: 12 stages (prebuild → cleanup)
- ✅ **Jobs**: 70+ jobs across all stages
- ✅ **Scripts**: Every job has script execution
- ✅ **Needs**: Complex DAG with cross-stage dependencies

### Variables (proj5 enhanced)
```yaml
Global variables:
  - PROJECT_NAME, VERSION, BUILD_DATE
  - Docker config (DOCKER_REGISTRY, DOCKER_IMAGE_BASE, DOCKER_BUILDKIT)
  - App config (APP_ENV, LOG_LEVEL, MAX_RETRIES, TIMEOUT_SECONDS)
  - Database config (DB_HOST, DB_PORT, DB_NAME)
  - Service URLs (REDIS_URL, ELASTICSEARCH_URL)
  - Build optimization (CARGO_HOME, GO_CACHE_DIR)
  - Feature flags (ENABLE_*)

Job-specific variables:
  - Per-service environment variables
  - Database credentials
  - Test configuration

Dynamic variables:
  - dotenv artifacts for build IDs
  - Runtime-generated variables
```

### Artifacts (proj4, proj6 enhanced)
```yaml
Types:
  - Build artifacts (dist/, build/, binaries)
  - Test reports (JUnit, coverage)
  - Security reports (SAST, dependency scanning)
  - Performance reports (k6 metrics)
  - Code quality reports
  - dotenv files

Features:
  - Expiration times (1 hour, 2 hours, 1 week)
  - Conditional artifacts (when: always for tests)
  - Path-based artifacts
  - Report-type artifacts
```

### Services (proj7 enhanced)
```yaml
PostgreSQL:
  - Used in: backend integration, frontend integration, API tests, migration checks
  - Versions: postgres:15-alpine
  - With health checks and wait conditions

Redis:
  - Used in: multiple integration tests
  - Service alias configuration
  - Connection URL patterns

Elasticsearch:
  - Used in: backend integration tests
  - Custom command for disabling security
  - Health check with curl

Docker-in-Docker:
  - Used in: all package jobs
  - TLS cert directory configuration
  - Registry login integration
```

### Rules (proj8 enhanced)
```yaml
Branch-based:
  - if: $CI_COMMIT_BRANCH == "main"
  - if: $CI_COMMIT_BRANCH == "develop"

Change-based:
  - changes: services/frontend/**/*
  - changes: services/backend/**/*
  - changes: services/api/**/*

Variable-based:
  - if: $ENABLE_SECURITY_SCANNING == "true"
  - if: $ENABLE_PERFORMANCE_TESTS == "true"

Pipeline source:
  - if: $CI_PIPELINE_SOURCE == "schedule"
  - if: $CI_PIPELINE_SOURCE == "merge_request_event"

Manual triggers:
  - when: manual (production deployments)
  - when: always (notification jobs)
```

### Cache (proj9 enhanced)
```yaml
Global cache:
  key: "global-${CI_COMMIT_REF_SLUG}"
  paths: [.cache/, tmp/]
  policy: pull-push

Service-specific caches:
  Node.js: node_modules/, .npm/
  Ruby: vendor/ruby/, .bundle/
  Python: .venv/, .pip-cache/
  Go: .go-cache/

Dynamic keys:
  - node-${CI_COMMIT_REF_SLUG}
  - ruby-${CI_COMMIT_REF_SLUG}
  - python-${CI_COMMIT_REF_SLUG}
  - go-${CI_COMMIT_REF_SLUG}

Policies:
  - pull-push (default)
  - pull (test jobs)
```

### Before/After Scripts (proj10 enhanced)
```yaml
Global before_script:
  - Pipeline metadata logging
  - Build timestamp export

Global after_script:
  - Job completion logging
  - Duration calculation

Job-specific:
  - Service health checks
  - Database setup
  - Custom initialization

!reference usage:
  - Inherit and extend global scripts
  - Compose multiple script blocks
```

### Includes (proj11 enhanced)
```yaml
.gitlab/ci/frontend.yml:
  - Frontend-specific templates
  - Dependency audit jobs
  - Bundle analysis

.gitlab/ci/backend.yml:
  - Backend-specific templates
  - Database migration checks
  - Gem audit

.gitlab/ci/security.yml:
  - Container image scanning
  - License compliance

.gitlab/ci/monitoring.yml:
  - Child pipeline configuration
  - Prometheus/Grafana setup
```

### YAML Anchors (proj12 enhanced)
```yaml
&base_config: retry, timeout, interruptible
&docker_config: image, services, variables, tags
&node_config: image, cache
&ruby_config: image, cache
&python_config: image, cache

Merge usage:
  <<: *base_config
  <<: *docker_config
  <<: *node_config
```

### Extends (proj13 enhanced)
```yaml
Inheritance chain:
  .base_job
    └── .test_job (adds coverage, artifacts)
    └── .deploy_job (adds retry, timeout overrides)
    └── .docker_build_job (adds docker config)

Hidden templates:
  .base_job: Common retry/timeout/tags
  .test_job: Test-specific artifacts and reports
  .deploy_job: Deployment-specific configuration
  .docker_build_job: Docker image building template
  .frontend_base: Frontend language setup
  .backend_base: Backend language setup
  .security_base: Security job configuration
```

### Retry & Timeout (proj14 enhanced)
```yaml
Simple retry:
  retry: 2

Conditional retry:
  retry:
    max: 2
    when:
      - runner_system_failure
      - stuck_or_timeout_failure
      - api_failure

Timeout:
  timeout: 1h  (base jobs)
  timeout: 30m (deploy jobs)
  timeout: 15m (production deploys)

Interruptible:
  interruptible: true  (most jobs)
  interruptible: false (deploy jobs)
```

### Reports (proj15 enhanced)
```yaml
Test reports:
  - junit: JUnit XML for test results
  - coverage_report: Cobertura format

Security reports:
  - sast: Semgrep/SAST results
  - dependency_scanning: Trivy scan results

Quality reports:
  - codequality: Code Climate analysis

Performance reports:
  - performance: k6 metrics (JSON)

dotenv reports:
  - Used for build IDs and image tags
```

### Child Pipelines (proj16 enhanced)
```yaml
Trigger:
  trigger:
    include: .gitlab/ci/monitoring.yml
    strategy: depend

Variables passed:
  - DEPLOYMENT_ID: ${CI_PIPELINE_ID}
  - ENVIRONMENT: production

Child pipeline stages:
  - setup (Prometheus, Grafana, AlertManager)
  - verify (monitoring health checks)
```

### Matrix (proj17 enhanced)
```yaml
3D Matrix:
  parallel:
    matrix:
      - SERVICE: [frontend, backend, api]
        ENV: [development, staging]
        RUNNER: [linux, alpine]

Generates: 3 × 2 × 2 = 12 parallel jobs

Variable expansion:
  - ${SERVICE}
  - ${ENV}
  - ${RUNNER}
```

### Resource Groups (proj18 enhanced)
```yaml
Staging:
  - staging-frontend
  - staging-backend
  - staging-api

Production:
  - production-frontend
  - production-backend
  - production-api

Ensures sequential deployment per service
Prevents conflicts and race conditions
```

## Unique Combinations in proj20

These features are combined in ways not seen in individual projects:

1. **Services + Matrix**: Matrix jobs with different service configurations
2. **Extends + Anchors**: Both template systems used together
3. **Includes + Child Pipelines**: Multi-level pipeline composition
4. **Resource Groups + Manual Jobs**: Coordinated manual deployments
5. **dotenv + needs**: Dynamic variables passed through DAG
6. **Rules + Changes + Matrix**: Complex conditional matrix jobs
7. **Before/After + !reference + Extends**: Multi-level script composition
8. **Reports + Artifacts + Dependencies**: Full test result pipeline
9. **Cache + Services + Matrix**: Language-specific caches per matrix job
10. **Multi-stage Environments**: Dev (parallel) → Stage (serial) → Prod (manual)

## Complexity Metrics

| Metric | Count |
|--------|-------|
| Total Stages | 12 |
| Total Jobs | 70+ |
| Hidden Templates | 10 |
| Included Files | 4 |
| YAML Anchors | 7 |
| Services Used | 5 (PostgreSQL, Redis, Elasticsearch, Docker, Nginx) |
| Languages | 4 (JavaScript, Ruby, Python, Go) |
| Environments | 12 (3 services × 3 envs + stop actions) |
| Resource Groups | 6 |
| Matrix Dimensions | 3 (generates 12 jobs) |
| Child Pipelines | 1 |
| Report Types | 6 (JUnit, coverage, SAST, dependency, performance, codequality) |

## What Makes This Comprehensive

1. **Scale**: Realistic monorepo with 4 services and 70+ jobs
2. **Depth**: Multi-level inheritance and includes
3. **Breadth**: All major GitLab CI features in one pipeline
4. **Realism**: Actual deployment workflow (dev → staging → prod)
5. **Complexity**: Cross-feature interactions and dependencies
6. **Services**: Real service orchestration patterns
7. **Reports**: Full testing and security reporting pipeline
8. **Gates**: Proper testing gates before deployment
9. **Coordination**: Resource groups preventing conflicts
10. **Extensibility**: Child pipelines for post-deployment tasks

This is not just a feature checklist—it's a realistic, production-grade pipeline that tests parser edge cases and feature interactions.
