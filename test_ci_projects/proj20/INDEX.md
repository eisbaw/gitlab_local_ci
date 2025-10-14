# proj20 - Complete File Index

## Overview
This directory contains a comprehensive "kitchen sink" GitLab CI pipeline that combines ALL features from proj1-proj19.

## Quick Reference

- **Main Pipeline**: `.gitlab-ci.yml` (1068 lines)
- **Total Files**: 28 files
- **Total Size**: ~252KB
- **Services**: 4 (frontend, backend, api, workers)
- **Languages**: Node.js, Ruby, Python, Go

## Documentation Files

| File | Purpose | Size |
|------|---------|------|
| `README.md` | Main documentation with feature overview | 11KB |
| `FEATURES.md` | Feature mapping from proj1-19 | 11KB |
| `TESTING_GUIDE.md` | Parser testing guide | 9KB |
| `PROJECT_SUMMARY.md` | Quick stats and summary | 9KB |
| `INDEX.md` | This file - complete file listing | - |

## CI Configuration Files

### Main Configuration
| File | Jobs | Purpose |
|------|------|---------|
| `.gitlab-ci.yml` | 50+ | Main pipeline with all stages |

### Included Configurations
| File | Jobs | Purpose |
|------|------|---------|
| `.gitlab/ci/frontend.yml` | 2 | Frontend-specific jobs |
| `.gitlab/ci/backend.yml` | 2 | Backend-specific jobs |
| `.gitlab/ci/security.yml` | 2 | Security scanning jobs |
| `.gitlab/ci/monitoring.yml` | 4 | Child pipeline for monitoring |

**Total Jobs**: 70+ (including matrix expansion)

## Service Files

### Frontend (Node.js/React)
```
services/frontend/
├── Dockerfile              # Multi-stage Docker build
├── package.json            # Node.js dependencies
├── nginx.conf              # Nginx web server config
├── src/
│   └── index.js           # React application entry
└── tests/
    └── example.test.js    # Jest unit tests
```

### Backend (Ruby/Rails)
```
services/backend/
├── Dockerfile              # Ruby container build
├── Gemfile                 # Ruby dependencies
├── Gemfile.lock            # Locked dependency versions
└── spec/
    └── example_spec.rb    # RSpec unit tests
```

### API (Python/FastAPI)
```
services/api/
├── Dockerfile              # Python container build
├── requirements.txt        # Python dependencies
├── src/
│   └── main.py            # FastAPI application
└── tests/
    └── unit/
        └── test_main.py   # Pytest unit tests
```

### Workers (Go)
```
services/workers/
├── Dockerfile              # Go binary container
├── go.mod                  # Go module definition
├── go.sum                  # Module checksums
├── cmd/
│   └── worker/
│       └── main.go        # Worker entry point
└── worker_test.go         # Go unit tests
```

## Configuration Files

| File | Purpose |
|------|---------|
| `.gitignore` | Git ignore patterns for all services |

## File Breakdown by Type

### YAML Files (5)
- `.gitlab-ci.yml` - Main pipeline configuration
- `.gitlab/ci/frontend.yml` - Frontend jobs
- `.gitlab/ci/backend.yml` - Backend jobs
- `.gitlab/ci/security.yml` - Security jobs
- `.gitlab/ci/monitoring.yml` - Monitoring child pipeline

### Documentation (5)
- `README.md` - Main documentation
- `FEATURES.md` - Feature mapping
- `TESTING_GUIDE.md` - Testing guide
- `PROJECT_SUMMARY.md` - Project summary
- `INDEX.md` - This file

### Dockerfiles (4)
- `services/frontend/Dockerfile`
- `services/backend/Dockerfile`
- `services/api/Dockerfile`
- `services/workers/Dockerfile`

### Dependency Files (5)
- `services/frontend/package.json` (Node.js)
- `services/backend/Gemfile` (Ruby)
- `services/backend/Gemfile.lock` (Ruby lock)
- `services/api/requirements.txt` (Python)
- `services/workers/go.mod` (Go)
- `services/workers/go.sum` (Go checksums)

### Source Code (5)
- `services/frontend/src/index.js` (JavaScript)
- `services/backend/spec/example_spec.rb` (Ruby)
- `services/api/src/main.py` (Python)
- `services/api/tests/unit/test_main.py` (Python test)
- `services/workers/cmd/worker/main.go` (Go)

### Test Files (4)
- `services/frontend/tests/example.test.js`
- `services/backend/spec/example_spec.rb`
- `services/api/tests/unit/test_main.py`
- `services/workers/worker_test.go`

### Configuration (2)
- `services/frontend/nginx.conf`
- `.gitignore`

## Quick Start

### 1. Read the Documentation
Start with `README.md` for a comprehensive overview.

### 2. Understand the Features
Read `FEATURES.md` to see how proj1-19 features map to this project.

### 3. Test the Parser
Follow `TESTING_GUIDE.md` to validate parser implementation.

### 4. Check the Summary
Review `PROJECT_SUMMARY.md` for quick stats and metrics.

## Key Features Demonstrated

### Pipeline Structure
- 12 stages (prebuild → cleanup)
- 70+ jobs with complex dependencies
- DAG with cross-stage needs
- Parallel and sequential execution

### YAML Techniques
- **Anchors**: 7 reusable configurations
- **Extends**: 10 hidden templates
- **Includes**: 4 external files
- **!reference**: Script composition

### CI Features
- **Variables**: Global, job-specific, dotenv
- **Artifacts**: Paths, reports, dependencies
- **Services**: PostgreSQL, Redis, Elasticsearch, Docker
- **Rules**: Branch, changes, variables, manual
- **Cache**: Global and per-service
- **Reports**: JUnit, coverage, SAST, performance
- **Matrix**: 3D parallelization (3×2×2)
- **Resource Groups**: 6 deployment coordinators
- **Environments**: 12 (dev, staging, prod × 3 + stops)
- **Child Pipelines**: Monitoring setup

### Multi-Service Monorepo
- 4 microservices
- 4 programming languages
- Independent build pipelines
- Coordinated deployments
- Shared testing infrastructure

## Usage Examples

```bash
# Parse the main configuration
gitlab-ci-local --list

# Show all jobs
gitlab-ci-local --jobs

# Validate DAG
gitlab-ci-local --validate

# Run specific stage
gitlab-ci-local --stage test

# Simulate with branch
gitlab-ci-local --branch main --dry-run

# Test file changes
gitlab-ci-local --changes "services/frontend/**/*" --dry-run
```

## Parser Test Checklist

- [ ] Parse main YAML without errors
- [ ] Process all 4 includes
- [ ] Generate 70+ jobs
- [ ] Expand matrix to 12 jobs
- [ ] Resolve all YAML anchors
- [ ] Apply all extends templates
- [ ] Build valid DAG
- [ ] Identify all stages
- [ ] Track all artifacts
- [ ] Parse all services
- [ ] Evaluate all rules
- [ ] Handle all reports
- [ ] Process child pipeline
- [ ] Resolve resource groups

## Expected Outputs

### Stages (12)
1. prebuild
2. build
3. test
4. security
5. quality
6. package
7. deploy_dev
8. integration
9. deploy_stage
10. performance
11. deploy_prod
12. cleanup

### Job Count by Stage
- prebuild: 5
- build: 4
- test: 8 (+ 12 matrix jobs)
- security: 7
- quality: 3
- package: 4
- deploy_dev: 6
- integration: 1
- deploy_stage: 4
- performance: 2
- deploy_prod: 4
- cleanup: 3

**Total**: 70+ jobs

## Integration with Parser

This project is designed to test:

1. **YAML Parsing**: Complex nested structures
2. **Job Generation**: Templates and matrix expansion
3. **DAG Construction**: Cross-stage dependencies
4. **Rule Evaluation**: Multiple condition types
5. **Variable Resolution**: Multi-level expansion
6. **Service Orchestration**: Multiple databases
7. **Artifact Tracking**: Dependencies and reports
8. **Include Processing**: Multiple file merging

## Notes

- This is a **test fixture**, not production code
- File contents are minimal but representative
- Focus is on CI configuration completeness
- Demonstrates realistic monorepo patterns
- Combines features that stress-test parsers

## Related Projects

- **proj1-proj18**: Individual feature tests
- **proj19**: [Not created]
- **proj21+**: Future advanced features

## Version

- **Version**: 2.0.0
- **Created**: 2025-10-13
- **Purpose**: Comprehensive GitLab CI feature testing
- **Status**: Complete

---

**Last Updated**: 2025-10-13
**Total Size**: ~252KB
**Total Files**: 28
**Main Config**: 1068 lines
