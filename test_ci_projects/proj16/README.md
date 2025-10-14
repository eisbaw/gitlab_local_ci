# Proj16 - Child Pipeline Triggering Test

This project tests GitLab CI child pipeline triggering functionality.

## Features Tested

### Parent Pipeline (`.gitlab-ci.yml`)
- **trigger_child1**: Triggers child1 pipeline with development variables
- **trigger_child2**: Triggers child2 pipeline with production variables
- **trigger_child_with_rules**: Conditional trigger based on branch rules
- **strategy: depend**: Parent waits for child pipeline completion
- **Variables passed**: CHILD_VAR, ENVIRONMENT, and inherited PARENT_VAR

### Child Pipeline 1 (`.gitlab/ci/child1.yml`)
- **Stages**: build, test
- **Jobs**:
  - `child1_build`: Builds and creates artifacts
  - `child1_test`: Runs tests with dependencies
  - `child1_integration`: Conditional integration tests (development only)
- **Variables**: Receives CHILD_VAR, ENVIRONMENT, inherits PARENT_VAR

### Child Pipeline 2 (`.gitlab/ci/child2.yml`)
- **Stages**: prepare, deploy, verify
- **Jobs**:
  - `child2_prepare`: Prepares deployment
  - `child2_deploy`: Deploys to environment
  - `child2_verify`: Verifies deployment (production only)
  - `child2_rollback`: Rollback job (runs on failure)
- **Variables**: Receives CHILD_VAR, ENVIRONMENT, inherits PARENT_VAR
- **Environment**: Dynamic environment based on ENVIRONMENT variable

## Key Testing Points

1. **Trigger Keyword**: Tests `trigger:` with `include:` for child pipelines
2. **Strategy Depend**: Parent pipeline waits for child completion
3. **Variable Passing**: Variables are passed from parent to child
4. **Variable Inheritance**: Parent variables available in child pipelines
5. **Conditional Triggers**: Rules on trigger jobs
6. **Conditional Child Jobs**: Rules within child pipelines based on passed variables
7. **Artifacts in Children**: Child pipelines can create artifacts
8. **Dependencies in Children**: Child jobs can depend on other child jobs
9. **Environments in Children**: Child pipelines can deploy to environments
10. **Failure Handling**: Child jobs with `when: on_failure`

## Expected Behavior

When the parent pipeline runs:
1. Both `trigger_child1` and `trigger_child2` start simultaneously
2. Child1 pipeline runs with ENVIRONMENT="development"
3. Child2 pipeline runs with ENVIRONMENT="production"
4. Parent waits for both children to complete (strategy: depend)
5. Conditional jobs run based on ENVIRONMENT variable
6. `trigger_child_with_rules` only runs on main branch

## Testing with gitlab-ci-local

```bash
# Run the parent pipeline
gitlab-ci-local

# The tool should:
# - Detect trigger jobs
# - Parse child pipeline includes
# - Execute child pipelines with passed variables
# - Wait for children when strategy: depend is set
```
