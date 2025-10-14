# Testing Guide for proj20

## Purpose

This comprehensive test project is designed to validate that a GitLab CI parser/simulator can handle:

1. **All major GitLab CI features** in combination
2. **Complex job dependencies** and DAG resolution
3. **Real-world pipeline patterns** used in production
4. **Edge cases** and feature interactions

## What to Test

### 1. YAML Parsing
- [ ] Parse main `.gitlab-ci.yml` without errors
- [ ] Process all 4 included files
- [ ] Resolve YAML anchors and merge keys
- [ ] Handle extends inheritance chains
- [ ] Process hidden jobs (starting with `.`)

### 2. Job Generation
- [ ] Generate all expected jobs (70+ total)
- [ ] Expand matrix jobs (12 jobs from 1 definition)
- [ ] Apply extends to create concrete jobs
- [ ] Merge anchor references correctly
- [ ] Include jobs from external files

### 3. Stage Resolution
- [ ] Identify all 12 stages in correct order
- [ ] Assign jobs to correct stages
- [ ] Handle jobs with explicit stage assignment

### 4. DAG Construction
- [ ] Build dependency graph from `needs` keywords
- [ ] Handle cross-stage dependencies
- [ ] Identify parallel execution opportunities
- [ ] Detect circular dependencies (should be none)
- [ ] Validate all needs references exist

### 5. Variable Resolution
- [ ] Expand global variables
- [ ] Apply job-specific variables
- [ ] Handle variable references (${VAR})
- [ ] Process predefined CI/CD variables
- [ ] Track dotenv artifact variables

### 6. Rules Evaluation
- [ ] Evaluate branch-based rules
- [ ] Check variable-based conditions
- [ ] Process file change patterns
- [ ] Handle pipeline source conditions
- [ ] Apply manual/always/on_success conditions

### 7. Service Configuration
- [ ] Parse service definitions
- [ ] Handle service aliases
- [ ] Process service variables
- [ ] Support multiple services per job

### 8. Artifact Tracking
- [ ] Track artifact paths
- [ ] Handle report artifacts
- [ ] Process expiration times
- [ ] Manage artifact dependencies between jobs
- [ ] Handle dotenv artifacts

### 9. Cache Configuration
- [ ] Parse global cache
- [ ] Override with job-specific cache
- [ ] Generate cache keys with variables
- [ ] Handle cache policies (pull-push, pull, push)

### 10. Environment Handling
- [ ] Parse environment names
- [ ] Handle environment URLs
- [ ] Process environment actions (deploy, stop)
- [ ] Track environment references

### 11. Resource Groups
- [ ] Identify resource group assignments
- [ ] Understand mutual exclusion requirements

### 12. Child Pipelines
- [ ] Parse trigger configuration
- [ ] Track trigger strategy (depend)
- [ ] Handle variable passing to child pipeline
- [ ] Process child pipeline YAML

### 13. Reports
- [ ] Identify JUnit report paths
- [ ] Track coverage reports
- [ ] Handle SAST reports
- [ ] Process dependency scanning reports
- [ ] Parse performance reports
- [ ] Track code quality reports

## Expected Outputs

### Job List (Sample)
```
Stage: prebuild
  - validate:yaml
  - validate:dependencies
  - lint:frontend
  - lint:backend
  - lint:api

Stage: build
  - build:frontend
  - build:backend
  - build:api
  - build:workers

Stage: test
  - test:frontend:unit
  - test:frontend:integration
  - test:backend:unit
  - test:backend:integration
  - test:api:unit
  - test:api:integration
  - test:workers
  - test:matrix:compatibility (×12 via matrix)

Stage: security
  - security:sast
  - security:dependency-scanning
  - security:secrets
  - audit:frontend:dependencies (from include)
  - audit:backend:dependencies (from include)
  - security:container:scan (from include, ×4 via matrix)
  - security:license:check (from include)

Stage: quality
  - quality:codeclimate
  - quality:metrics
  - bundle:frontend:analyze (from include)

Stage: package
  - package:frontend
  - package:backend
  - package:api
  - package:workers

Stage: deploy_dev
  - deploy:dev:frontend
  - deploy:dev:backend
  - deploy:dev:api
  - stop:dev:frontend
  - stop:dev:backend
  - stop:dev:api

Stage: integration
  - integration:e2e

Stage: deploy_stage
  - deploy:staging:frontend
  - deploy:staging:backend
  - deploy:staging:api
  - database:migrations:check (from include)

Stage: performance
  - performance:load-test
  - performance:stress-test

Stage: deploy_prod
  - deploy:prod:frontend
  - deploy:prod:backend
  - deploy:prod:api
  - trigger:monitoring-setup

Stage: cleanup
  - cleanup:old-images
  - cleanup:artifacts
  - notify:pipeline-status
```

### DAG Relationships (Sample)

```
build:frontend → test:frontend:unit → package:frontend → deploy:dev:frontend
build:backend → test:backend:unit → package:backend → deploy:dev:backend

integration:e2e needs:
  - deploy:dev:frontend
  - deploy:dev:backend
  - deploy:dev:api

deploy:staging:frontend needs:
  - package:frontend
  - integration:e2e

performance:load-test needs:
  - deploy:staging:frontend
  - deploy:staging:backend
  - deploy:staging:api

deploy:prod:frontend needs:
  - deploy:staging:frontend
  - performance:load-test
```

### Variable Examples

```yaml
Global:
  PROJECT_NAME: "monorepo-platform"
  VERSION: "2.0.0"
  DOCKER_REGISTRY: "registry.example.com"
  DOCKER_IMAGE_BASE: "registry.example.com/monorepo-platform"

Job-specific (test:frontend:integration):
  POSTGRES_DB: "test_db"
  POSTGRES_USER: "test_user"
  DATABASE_URL: "postgresql://test_user:test_pass@postgres:5432/test_db"
  REDIS_URL: "redis://redis:6379"
  NODE_ENV: "test"

Predefined (examples):
  CI_PIPELINE_ID: "123456"
  CI_COMMIT_SHA: "abc123..."
  CI_COMMIT_REF_NAME: "main"
  CI_PROJECT_NAME: "monorepo-platform"
```

## Edge Cases to Verify

1. **Deep inheritance**: `.base_job` → `.test_job` → `test:frontend:unit`
2. **Multiple inheritance sources**: YAML anchors + extends + includes
3. **Complex rules**: Branch + changes + variables combined
4. **Service dependencies**: Jobs with 3+ services
5. **Resource coordination**: Multiple jobs sharing resource groups
6. **Matrix expansion**: 3-dimensional matrix (3×2×2)
7. **Child pipeline variables**: Parent variables passed to child
8. **Dynamic cache keys**: Variables in cache key patterns
9. **Artifact chains**: Job C needs artifacts from Job A and Job B
10. **Script composition**: !reference in before_script

## Common Parser Issues

### Issue 1: Circular Dependencies
**Expected**: None should exist in this pipeline
**Test**: Run DAG validation

### Issue 2: Missing Needs References
**Expected**: All needs references should resolve to valid jobs
**Test**: Validate all `needs:` entries exist

### Issue 3: Matrix Variable Expansion
**Expected**: 12 jobs from test:matrix:compatibility
**Test**: Count expanded matrix jobs

### Issue 4: Include Processing
**Expected**: Jobs from included files appear in final pipeline
**Test**: Verify `audit:frontend:dependencies` exists

### Issue 5: Extends Resolution
**Expected**: Job inherits all properties from template
**Test**: Check `test:frontend:unit` has properties from `.test_job` and `.base_job`

### Issue 6: Anchor Merging
**Expected**: Jobs using `<<: *node_config` have image and cache
**Test**: Verify `lint:frontend` has correct image

### Issue 7: Rules Evaluation
**Expected**: Jobs with changes rules know their file patterns
**Test**: Check `lint:frontend` has `changes: services/frontend/**/*`

### Issue 8: Service Aliases
**Expected**: Services have correct aliases for connection
**Test**: Verify PostgreSQL alias is `postgres` in DATABASE_URL

## Performance Benchmarks

For reference, this pipeline should:
- Parse in < 5 seconds
- Generate 70+ jobs
- Build DAG with 150+ edges
- Process 4 included files
- Expand 1 matrix into 12 jobs
- Resolve 7 YAML anchors
- Process 10 extends templates

## Validation Commands

```bash
# List all jobs
gitlab-ci-local --list

# Show specific job details
gitlab-ci-local test:frontend:unit --describe

# Validate DAG
gitlab-ci-local --validate

# Show stage order
gitlab-ci-local --stages

# Dry run specific stage
gitlab-ci-local --stage test --dry-run

# Show variable expansion
gitlab-ci-local test:frontend:unit --show-variables
```

## Success Criteria

A parser successfully handles this project if it:

1. ✅ Parses without errors
2. ✅ Generates all expected jobs (70+)
3. ✅ Correctly expands matrix (12 jobs)
4. ✅ Builds valid DAG without cycles
5. ✅ Resolves all variable references
6. ✅ Processes all includes
7. ✅ Handles all extends chains
8. ✅ Evaluates all rules correctly
9. ✅ Tracks all artifacts and dependencies
10. ✅ Identifies all resource groups
11. ✅ Parses child pipeline trigger
12. ✅ Resolves all service configurations

## Known Limitations

This test project intentionally does **not** test:

- External includes (template, remote, project)
- Component includes (new GitLab 16+ feature)
- Workflow rules
- Default settings
- Image entrypoint/command overrides
- Coverage regex variations
- Merge train specific features
- Auto DevOps
- DAST/API fuzzing reports
- Terraform reports
- Kubernetes-specific features

These may be added in future test projects (proj21+).
