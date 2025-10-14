# Project 11: Include Directives and Job Overriding

This test project demonstrates GitLab CI's `include` directive functionality and how to override jobs from included files.

## Directory Structure

```
proj11/
├── .gitlab-ci.yml          # Main CI configuration
└── .gitlab/
    └── ci/
        ├── build.yml       # Build stage jobs
        ├── test.yml        # Test stage jobs
        └── deploy.yml      # Deploy stage jobs
```

## Features Demonstrated

### 1. Local File Includes
- Main `.gitlab-ci.yml` includes three separate YAML files using `local:` includes
- Each included file contains jobs for a specific stage
- Demonstrates modular CI/CD configuration

### 2. Job Templates
- `.build-template`, `.test-template`, `.deploy-template` in included files
- Jobs extend these templates for consistent configuration

### 3. Job Overriding
The main `.gitlab-ci.yml` overrides several jobs from included files:

- **build-app**: Complete script override with custom variables
- **integration-tests**: Partial override (allow_failure + script)
- **deploy-production**: Additional before_script and after_script steps

### 4. Additional Features
- Global variables defined in main file
- Default retry configuration
- New jobs added alongside included jobs (code-quality, verify-includes)
- Artifacts with expiration
- Environment definitions
- Manual deployment jobs

## Include Types Shown

```yaml
include:
  - local: '.gitlab/ci/build.yml'    # Include from same repository
  - local: '.gitlab/ci/test.yml'
  - local: '.gitlab/ci/deploy.yml'
```

## Override Patterns

### Complete Override
```yaml
build-app:
  variables:
    BUILD_TYPE: "optimized"
  script:
    - echo "Completely new script"
```

### Partial Override
```yaml
integration-tests:
  allow_failure: true  # Only override specific attributes
```

### Extend with Additional Steps
```yaml
deploy-production:
  before_script:
    - echo "Additional preparation..."
  after_script:
    - echo "Post-deployment tasks..."
```

## Testing

Run this pipeline with:
```bash
gitlab-ci-local
```

## Expected Pipeline

```
.pre        → verify-includes
build       → build-app, build-docker
test        → unit-tests, integration-tests, security-scan, code-quality
deploy      → deploy-staging, deploy-production, rollback-production
```

## Key Learning Points

1. **Include Directive**: Use `include: local:` to split large CI configurations
2. **Job Inheritance**: Jobs from included files can be completely or partially overridden
3. **Composition**: Combine base configurations with project-specific overrides
4. **Modularity**: Separate concerns by stage or functionality
5. **Reusability**: Templates in included files can be extended by multiple jobs
