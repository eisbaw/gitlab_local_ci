# Test Project 20: Comprehensive Kitchen Sink Pipeline

## Overview

This is a comprehensive test project that combines **ALL** features from proj1-proj19 into a single, realistic monorepo CI/CD pipeline. It represents a production-grade multi-service platform with complex deployment workflows.

## Architecture

This monorepo contains four microservices:

- **Frontend** (Node.js/React) - User-facing web application
- **Backend** (Ruby/Rails) - API and business logic server
- **API** (Python/FastAPI) - High-performance REST API
- **Workers** (Go) - Background job processing

## GitLab CI Features Demonstrated

### 1. **Basic Features**
- ✅ Multiple stages (12 stages total)
- ✅ Simple script execution
- ✅ Stage dependencies

### 2. **Variables**
- ✅ Global variables
- ✅ Job-specific variables
- ✅ Variable expansion (`${VAR}`)
- ✅ Predefined CI/CD variables
- ✅ dotenv artifacts for dynamic variables

### 3. **Artifacts**
- ✅ Artifact paths and expiration
- ✅ Artifact dependencies between jobs
- ✅ Report artifacts (JUnit, coverage, SAST, etc.)
- ✅ dotenv artifacts

### 4. **Services**
- ✅ PostgreSQL database
- ✅ Redis cache
- ✅ Elasticsearch search engine
- ✅ Docker-in-Docker (DinD)
- ✅ Service aliases
- ✅ Multiple services per job

### 5. **Rules**
- ✅ Conditional execution based on branch
- ✅ Conditional execution based on variables
- ✅ Changes-based rules (path triggers)
- ✅ Pipeline source rules
- ✅ Manual job triggers
- ✅ `when: always` and `when: manual`

### 6. **Cache**
- ✅ Global cache configuration
- ✅ Job-specific cache overrides
- ✅ Dynamic cache keys
- ✅ Cache policies (pull-push, pull, push)
- ✅ Multiple cache paths

### 7. **Includes**
- ✅ Local file includes
- ✅ Modular CI configuration
- ✅ Template sharing across jobs

### 8. **YAML Anchors**
- ✅ Anchor definitions (`&anchor`)
- ✅ Anchor references (`*alias`)
- ✅ Merge keys (`<<:`)
- ✅ Complex nested structures

### 9. **Extends**
- ✅ Hidden job templates (`.template`)
- ✅ Single-level extends
- ✅ Multi-level extends (inheritance chains)
- ✅ Value overriding
- ✅ Array merging

### 10. **Before/After Scripts**
- ✅ Global before_script
- ✅ Global after_script
- ✅ Job-specific overrides
- ✅ Script references with `!reference`

### 11. **Retry & Timeout**
- ✅ Simple retry counts
- ✅ Conditional retry (when clauses)
- ✅ Job timeouts
- ✅ Interruptible jobs

### 12. **Reports**
- ✅ JUnit test reports
- ✅ Coverage reports (Cobertura)
- ✅ SAST reports
- ✅ Dependency scanning reports
- ✅ Performance reports
- ✅ Code quality reports

### 13. **Triggers**
- ✅ Child pipeline triggers
- ✅ Trigger strategy: depend
- ✅ Variable passing to child pipelines
- ✅ Multi-stage trigger workflows

### 14. **Matrix Parallelization**
- ✅ `parallel:matrix` configuration
- ✅ Multi-dimensional matrix (SERVICE × ENV × RUNNER)
- ✅ Matrix variable expansion

### 15. **Resource Groups**
- ✅ Deployment coordination
- ✅ Exclusive access to environments
- ✅ Prevents concurrent deployments

### 16. **Environments**
- ✅ Environment names and URLs
- ✅ Multiple environments (dev, staging, production)
- ✅ Environment actions (deploy, stop)
- ✅ Manual environment control

### 17. **Advanced Features**
- ✅ Docker image building
- ✅ Multi-stage Dockerfiles
- ✅ Container registry integration
- ✅ Service health checks
- ✅ Database migrations
- ✅ E2E testing with Cypress
- ✅ Performance testing with k6
- ✅ Security scanning (Trivy, Semgrep)
- ✅ License compliance checking
- ✅ Bundle analysis

## Pipeline Flow

```
┌─────────────┐
│  Prebuild   │  Validation, linting, dependency checks
└──────┬──────┘
       ↓
┌─────────────┐
│   Build     │  Compile all services
└──────┬──────┘
       ↓
┌─────────────┐
│    Test     │  Unit & integration tests (with services)
└──────┬──────┘
       ↓
┌─────────────┐
│  Security   │  SAST, dependency scanning, secrets
└──────┬──────┘
       ↓
┌─────────────┐
│  Quality    │  Code quality analysis, metrics
└──────┬──────┘
       ↓
┌─────────────┐
│  Package    │  Build Docker images
└──────┬──────┘
       ↓
┌─────────────┐
│ Deploy Dev  │  Deploy to development (parallel)
└──────┬──────┘
       ↓
┌─────────────┐
│Integration  │  E2E tests on dev environment
└──────┬──────┘
       ↓
┌─────────────┐
│Deploy Stage │  Deploy to staging (with resource groups)
└──────┬──────┘
       ↓
┌─────────────┐
│Performance  │  Load and stress testing
└──────┬──────┘
       ↓
┌─────────────┐
│Deploy Prod  │  Manual production deployment (coordinated)
└──────┬──────┘
       ↓
┌─────────────┐
│  Cleanup    │  Post-deployment tasks
└─────────────┘
```

## Complex DAG Features

The pipeline demonstrates complex job dependencies using `needs`:

- Jobs can skip stages and start early if dependencies are met
- Parallel execution within stages
- Cross-stage dependencies
- Conditional needs based on rules

Example DAG:
```
build:frontend ──→ test:frontend:unit ──→ package:frontend ──→ deploy:dev:frontend
                                                                         ↓
                                                               integration:e2e
                                                                         ↓
build:backend  ──→ test:backend:unit  ──→ package:backend  ──→ deploy:staging:frontend
                                                                         ↓
build:api      ──→ test:api:unit      ──→ package:api      ──→ performance:load-test
                                                                         ↓
build:workers  ──→ test:workers       ──→ package:workers  ──→ deploy:prod:frontend (manual)
```

## Key Complexity Points

### 1. Service Dependencies
Multiple jobs use different service combinations:
- PostgreSQL for database testing
- Redis for caching tests
- Elasticsearch for search functionality
- Docker-in-Docker for image building

### 2. Multi-Language Support
- Node.js (Frontend)
- Ruby (Backend)
- Python (API)
- Go (Workers)

Each with language-specific:
- Package managers
- Test frameworks
- Build tools
- Cache strategies

### 3. Environment Progression
```
Development → Staging → Production
(parallel)    (serial)  (manual, serial)
```

- Development: Fast feedback, parallel deployments
- Staging: Gated by tests, with resource groups
- Production: Manual approval, coordinated rollout

### 4. Resource Groups
Ensures only one deployment runs at a time per environment:
- `staging-frontend`
- `staging-backend`
- `staging-api`
- `production-frontend`
- `production-backend`
- `production-api`

### 5. Child Pipelines
After production deployment, a child pipeline is triggered for:
- Monitoring setup (Prometheus, Grafana, AlertManager)
- Infrastructure configuration
- Post-deployment verification

## Testing Scenarios

This project tests the GitLab CI parser's ability to handle:

1. **Large pipeline complexity** (70+ jobs across 12 stages)
2. **Deep inheritance chains** (`.base_job` → `.test_job` → `test:frontend:unit`)
3. **Mixed YAML features** (anchors + extends + includes)
4. **Complex conditionals** (rules with changes, variables, branches)
5. **Service orchestration** (multiple databases and caches)
6. **Report aggregation** (JUnit, coverage, SAST, performance)
7. **Resource coordination** (resource groups preventing conflicts)
8. **Dynamic variables** (dotenv artifacts between jobs)
9. **Matrix explosions** (3×3 matrix = 9 jobs)
10. **Child pipeline management** (parent-child variable passing)

## Variables Reference

### Project Variables
- `PROJECT_NAME`: monorepo-platform
- `VERSION`: 2.0.0
- `DOCKER_REGISTRY`: registry.example.com

### Feature Flags
- `ENABLE_PERFORMANCE_TESTS`: true
- `ENABLE_SECURITY_SCANNING`: true
- `ENABLE_CODE_QUALITY`: true

### Service URLs
- `REDIS_URL`: redis://redis:6379
- `ELASTICSEARCH_URL`: http://elasticsearch:9200
- `DATABASE_URL`: postgresql://user:pass@host:5432/db

## Cache Strategy

Each service has its own cache key pattern:
- Frontend: `node-${CI_COMMIT_REF_SLUG}`
- Backend: `ruby-${CI_COMMIT_REF_SLUG}`
- API: `python-${CI_COMMIT_REF_SLUG}`
- Workers: `go-${CI_COMMIT_REF_SLUG}`

Global cache: `global-${CI_COMMIT_REF_SLUG}`

## Expected Parser Challenges

This pipeline will stress-test:

1. **DAG Resolution**: Complex needs relationships with cross-stage dependencies
2. **Rule Evaluation**: Multiple overlapping rules with changes patterns
3. **Variable Expansion**: Nested variable references and dotenv artifacts
4. **Template Merging**: YAML anchors + extends + includes all used together
5. **Service Resolution**: Multiple services with custom aliases and health checks
6. **Cache Key Generation**: Dynamic keys with predefined variable expansion
7. **Artifact Tracking**: Report artifacts with complex dependency chains
8. **Child Pipeline Triggering**: Variable passing and strategy handling
9. **Matrix Expansion**: Multi-dimensional parallel job generation
10. **Resource Groups**: Concurrency control across deployments

## Usage

```bash
# Validate the configuration
gitlab-ci-local --list

# Run specific stage
gitlab-ci-local --stage test

# Run specific job
gitlab-ci-local test:frontend:unit

# Dry run with variables
gitlab-ci-local --variable ENABLE_SECURITY_SCANNING=false --dry-run
```

## Notes

This is a **test fixture** designed to validate comprehensive GitLab CI feature support. A real-world pipeline this complex would typically be split into multiple pipelines or use more parent-child relationships.

The configuration intentionally combines features that might not normally appear together to ensure parser robustness.
