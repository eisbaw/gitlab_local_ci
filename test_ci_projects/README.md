# Test CI Projects - GitLab CI Feature Test Suite

## Overview

This directory contains 20 progressively complex GitLab CI test projects, designed to validate and test the `gitlab_ci_cli` tool's YAML parsing, pipeline creation, and simulation capabilities.

**Created:** 2025-10-13
**Purpose:** Comprehensive test fixtures for GitLab CI local simulator
**Complexity:** Simple → Comprehensive (proj1 → proj20)

## Project Index

| Project | Complexity | Primary Feature | Jobs | Files |
|---------|-----------|-----------------|------|-------|
| **proj1** | ⭐ | Minimal config | 1 | 1 |
| **proj2** | ⭐ | Multiple stages | 3 | 1 |
| **proj3** | ⭐⭐ | Parallel jobs | 4 | 1 |
| **proj4** | ⭐⭐ | Needs/DAG | 12 | 1 |
| **proj5** | ⭐⭐ | Variables | 7 | 1 |
| **proj6** | ⭐⭐⭐ | Artifacts | 10 | 1 |
| **proj7** | ⭐⭐⭐ | Services | 8 | 1 |
| **proj8** | ⭐⭐⭐ | Rules/Conditions | 15 | 1 |
| **proj9** | ⭐⭐⭐ | Cache | 11 | 1 |
| **proj10** | ⭐⭐⭐ | Hooks (before/after) | 12 | 1 |
| **proj11** | ⭐⭐⭐⭐ | Includes | 10 | 5 |
| **proj12** | ⭐⭐⭐⭐ | YAML Anchors | 15 | 1 |
| **proj13** | ⭐⭐⭐⭐ | Extends | 12 | 1 |
| **proj14** | ⭐⭐⭐⭐ | Retry/Timeout | 10 | 1 |
| **proj15** | ⭐⭐⭐⭐ | Reports/Coverage | 8 | 1 |
| **proj16** | ⭐⭐⭐⭐⭐ | Child Pipelines | 13 | 4 |
| **proj17** | ⭐⭐⭐⭐⭐ | Matrix/Parallel | 12+ (85 expanded) | 1 |
| **proj18** | ⭐⭐⭐⭐⭐ | Resource Groups | 10 | 1 |
| **proj19** | ⭐⭐⭐⭐⭐ | Complex DAG | 23 | 1 |
| **proj20** | ⭐⭐⭐⭐⭐⭐ | Kitchen Sink | 70+ | 31 |

## Feature Coverage

### Basic Features (proj1-3)
- ✅ Single job execution
- ✅ Multiple stages (sequential)
- ✅ Parallel jobs within stages
- ✅ Stage-based ordering

### Intermediate Features (proj4-10)
- ✅ Needs-based DAG parallelism
- ✅ Variable definition and expansion
- ✅ Artifact creation and consumption
- ✅ Service containers (Docker, PostgreSQL, Redis, etc.)
- ✅ Conditional execution (rules, when, only/except)
- ✅ Cache configuration (keys, policies)
- ✅ Before/after script hooks

### Advanced Features (proj11-15)
- ✅ YAML file inclusion
- ✅ YAML anchors and aliases
- ✅ Job templates with extends
- ✅ Retry logic and timeouts
- ✅ Test reports (JUnit, Cobertura)
- ✅ Coverage extraction

### Complex Features (proj16-19)
- ✅ Child/parent pipeline triggering
- ✅ Matrix parallelization
- ✅ Simple parallel splits
- ✅ Resource groups (deployment locking)
- ✅ Environment management
- ✅ Complex multi-service DAGs

### Comprehensive (proj20)
- ✅ All features combined
- ✅ Realistic monorepo setup
- ✅ Multi-language services
- ✅ Production-grade patterns

## Project Descriptions

### proj1 - Minimal Configuration
**Complexity:** ⭐
**Purpose:** Validate basic YAML parsing

The simplest possible GitLab CI config:
```yaml
test:
  script:
    - echo "Hello World"
```

### proj2 - Multiple Stages
**Complexity:** ⭐
**Purpose:** Test stage-based sequential execution

Three stages (build, test, deploy) with one job each, demonstrating sequential stage ordering.

### proj3 - Parallel Jobs
**Complexity:** ⭐⭐
**Purpose:** Test parallel execution within stages

Multiple jobs in the test stage (unit, integration, lint) that can run simultaneously.

### proj4 - Needs Dependencies
**Complexity:** ⭐⭐
**Purpose:** Test DAG-based parallelism

12 jobs with explicit `needs` dependencies, allowing jobs to start before their stage without waiting for all previous stages.

### proj5 - Variables
**Complexity:** ⭐⭐
**Purpose:** Test variable handling and expansion

Global variables, job-specific variables, predefined CI variables, and variable expansion patterns including `${VAR}` syntax.

### proj6 - Artifacts
**Complexity:** ⭐⭐⭐
**Purpose:** Test artifact passing between jobs

Jobs producing artifacts with various configurations (paths, names, expiration, reports), and jobs consuming artifacts via dependencies.

### proj7 - Services
**Complexity:** ⭐⭐⭐
**Purpose:** Test service container configuration

Jobs using service containers (PostgreSQL, Redis, MySQL, MongoDB, Docker-in-Docker) with aliases and environment configuration.

### proj8 - Rules and Conditions
**Complexity:** ⭐⭐⭐
**Purpose:** Test conditional job execution

Branch-based conditions, merge request pipelines, manual jobs, and various `when` conditions (on_success, on_failure, manual, always).

### proj9 - Cache Configuration
**Complexity:** ⭐⭐⭐
**Purpose:** Test cache key generation and policies

Global cache, job-specific overrides, static/dynamic cache keys, and cache policies (pull, push, pull-push).

### proj10 - Hooks
**Complexity:** ⭐⭐⭐
**Purpose:** Test before_script and after_script

Global hooks, job-specific overrides, hook disabling, and execution order when scripts fail.

### proj11 - Includes
**Complexity:** ⭐⭐⭐⭐
**Purpose:** Test YAML file inclusion

Main config including three local YAML files, demonstrating job composition and override patterns.

**Files:**
- `.gitlab-ci.yml` (main)
- `.gitlab/ci/build.yml`
- `.gitlab/ci/test.yml`
- `.gitlab/ci/deploy.yml`
- `README.md`

### proj12 - YAML Anchors
**Complexity:** ⭐⭐⭐⭐
**Purpose:** Test YAML anchor processing

Anchors (&), aliases (*), and merge keys (<<:) for configuration reuse, including multi-level composition.

### proj13 - Extends
**Complexity:** ⭐⭐⭐⭐
**Purpose:** Test extends mechanism

Hidden job templates (starting with .) and jobs extending from them, including multi-level extends chains.

### proj14 - Retry and Timeout
**Complexity:** ⭐⭐⭐⭐
**Purpose:** Test retry logic and timeouts

Various retry configurations (simple count, conditional with `when`), timeout specifications, and interruptible jobs.

### proj15 - Reports and Coverage
**Complexity:** ⭐⭐⭐⭐
**Purpose:** Test report parsing and coverage extraction

Coverage regex patterns, JUnit reports, Cobertura coverage, code quality reports, and SAST reports.

### proj16 - Child Pipelines
**Complexity:** ⭐⭐⭐⭐⭐
**Purpose:** Test child pipeline triggering

Parent pipeline triggering two child pipelines with variable passing and `strategy: depend` for synchronization.

**Files:**
- `.gitlab-ci.yml` (parent)
- `.gitlab/ci/child1.yml`
- `.gitlab/ci/child2.yml`
- `README.md`

### proj17 - Matrix and Parallel
**Complexity:** ⭐⭐⭐⭐⭐
**Purpose:** Test matrix expansion and parallel splits

Matrix parallelization (Ruby versions × OS × databases) generating 85+ parallel jobs, plus simple parallel splits.

### proj18 - Resource Groups
**Complexity:** ⭐⭐⭐⭐⭐
**Purpose:** Test resource group locking

Multiple deployment jobs sharing resource groups to prevent concurrent deployments, with environment management and auto-stop.

### proj19 - Complex DAG
**Complexity:** ⭐⭐⭐⭐⭐
**Purpose:** Test complex dependency resolution

23 jobs with intricate `needs` dependencies creating diamond patterns and complex multi-service build/test flows.

### proj20 - Kitchen Sink
**Complexity:** ⭐⭐⭐⭐⭐⭐
**Purpose:** Test all features together

Comprehensive monorepo pipeline combining ALL features from proj1-19 into a realistic production-grade configuration.

**Files:** 31 files including:
- Main `.gitlab-ci.yml` (1068 lines)
- 4 included YAML files
- 4 microservice directories
- 7 documentation files

**Features:** 70+ jobs, 12 stages, matrix parallelization, child pipelines, resource groups, all report types, complex DAG.

## Usage

### Testing Individual Features

```bash
# Test basic lint
gitlab_ci_cli lint --entry test_ci_projects/proj1/.gitlab-ci.yml

# Test DAG visualization
gitlab_ci_cli dag --entry test_ci_projects/proj4/.gitlab-ci.yml | dot -Tpng -o dag.png

# Test dry-run with runners
gitlab_ci_cli dry-run --entry test_ci_projects/proj3/.gitlab-ci.yml --runners ./runners
```

### Testing Progression

Start with simple projects and progress to complex:

```bash
# Level 1: Basic
for i in 1 2 3; do
  echo "Testing proj$i..."
  gitlab_ci_cli lint --entry test_ci_projects/proj$i/.gitlab-ci.yml
done

# Level 2: Intermediate
for i in 4 5 6 7 8 9 10; do
  echo "Testing proj$i..."
  gitlab_ci_cli lint --entry test_ci_projects/proj$i/.gitlab-ci.yml
done

# Level 3: Advanced
for i in 11 12 13 14 15; do
  echo "Testing proj$i..."
  gitlab_ci_cli lint --entry test_ci_projects/proj$i/.gitlab-ci.yml
done

# Level 4: Complex
for i in 16 17 18 19; do
  echo "Testing proj$i..."
  gitlab_ci_cli lint --entry test_ci_projects/proj$i/.gitlab-ci.yml
done

# Level 5: Comprehensive
gitlab_ci_cli lint --entry test_ci_projects/proj20/.gitlab-ci.yml
```

### Batch Testing

```bash
# Test all projects for YAML validity
find test_ci_projects -name ".gitlab-ci.yml" -type f | while read file; do
  echo "Linting $file..."
  gitlab_ci_cli lint --entry "$file" || echo "FAILED: $file"
done

# Generate all DAG visualizations
for i in {4,11,16,19,20}; do
  gitlab_ci_cli dag --entry test_ci_projects/proj$i/.gitlab-ci.yml \
    | dot -Tpng -o "dag_proj$i.png"
done
```

## Feature Mapping

| Feature | Projects |
|---------|----------|
| **Basic Execution** | proj1, proj2, proj3 |
| **DAG/Needs** | proj4, proj19 |
| **Variables** | proj5, proj20 |
| **Artifacts** | proj6, proj11, proj20 |
| **Services** | proj7, proj20 |
| **Rules/Conditions** | proj8, proj18, proj20 |
| **Cache** | proj9, proj20 |
| **Hooks** | proj10, proj20 |
| **Includes** | proj11, proj20 |
| **Anchors** | proj12, proj20 |
| **Extends** | proj13, proj20 |
| **Retry/Timeout** | proj14, proj20 |
| **Reports** | proj15, proj20 |
| **Child Pipelines** | proj16, proj20 |
| **Matrix** | proj17, proj20 |
| **Resource Groups** | proj18, proj20 |

## Statistics

**Total Projects:** 20
**Total YAML Files:** 35+
**Total Configuration Lines:** ~4,500+
**Total Jobs Defined:** ~250+
**Total Jobs After Expansion:** ~350+ (with matrix expansion)

**Complexity Distribution:**
- Simple (⭐): 2 projects
- Basic (⭐⭐): 2 projects
- Intermediate (⭐⭐⭐): 5 projects
- Advanced (⭐⭐⭐⭐): 5 projects
- Complex (⭐⭐⭐⭐⭐): 5 projects
- Comprehensive (⭐⭐⭐⭐⭐⭐): 1 project

## Testing Recommendations

### For Parser Development
1. Start with **proj1-3** to validate basic parsing
2. Progress to **proj4-10** for core features
3. Test **proj11-15** for advanced YAML features
4. Validate **proj16-19** for complex scenarios
5. Use **proj20** as comprehensive integration test

### For Feature Implementation
- **Variables:** proj5 → proj20
- **DAG:** proj4 → proj19 → proj20
- **Artifacts:** proj6 → proj11 → proj20
- **Services:** proj7 → proj20
- **Child Pipelines:** proj16 → proj20
- **Matrix:** proj17 → proj20

### For Performance Testing
- **Small:** proj1-3 (1-4 jobs)
- **Medium:** proj4-15 (7-15 jobs)
- **Large:** proj16-19 (10-23 jobs)
- **Extra Large:** proj20 (70+ jobs)

## Notes

- All projects contain only `.gitlab-ci.yml` configurations
- No actual source code or executables (just test fixtures)
- Scripts use `echo` statements for simulation
- Designed for dry-run testing, not real execution
- Progressive complexity allows incremental testing

## Contributing

To add new test projects:
1. Create `proj<N>` directory
2. Add `.gitlab-ci.yml` with focused feature test
3. Update this README with project description
4. Follow complexity progression (simple → complex)
5. Document primary feature and test purpose

## See Also

- [PRD.md](../PRD.md) - Product requirements
- [IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) - Implementation progress
- [MPED_IMPLEMENTATION_SUMMARY.md](../MPED_IMPLEMENTATION_SUMMARY.md) - MPED principles adherence
- [todo.md](../todo.md) - Implementation tasks
