# Testing Guide for CI Projects

## Overview

Each of the 20 test projects now includes a `justfile` with recipes for testing the GitLab CI configuration.

## Quick Start

### Test Individual Project

From the root directory:
```bash
just test-proj1    # Test minimal config
just test-proj4    # Test needs/DAG
just test-proj20   # Test kitchen sink
```

From within a project directory:
```bash
cd test_ci_projects/proj1
just test          # Run all tests (lint, dag, dry-run)
just lint          # Run only linting
just dag           # Run only DAG generation
just dry-run       # Run only dry-run simulation
```

### Test All Projects (e2e golden gate)

From the root directory, inside the dev shell:
```bash
just e2e          # snapshot every project, diff against projN.output_reference/
just e2e-update   # rewrite the goldens after an intended behaviour change
```

`just e2e` runs lint (text/json/junit), dag and dry-run for every project,
records stdout, stderr (`<file>.stderr`, only when non-empty, capped at 50
lines plus `# total_lines=N`) and the exit code of each, and fails on any
difference from the committed `projN.output_reference/`. Non-zero exit codes are expected data (proj11's lint
exit code is 1 because `.pre` is not supported yet, TASK-17). `metadata.txt` and `dag.svg` are
not compared.

When a behaviour fix lands, run `just e2e-update`, review
`git diff test_ci_projects/`, and explain each golden change in the commit
message. Never regenerate blindly: a golden may pin a known bug, and the diff
is where its fix becomes visible.

## Available Root Recipes

All recipes added to the root justfile:

| Recipe | Description |
|--------|-------------|
| `test-proj1` | Test project 1 - Minimal config |
| `test-proj2` | Test project 2 - Multiple stages |
| `test-proj3` | Test project 3 - Parallel jobs |
| `test-proj4` | Test project 4 - Needs/DAG |
| `test-proj5` | Test project 5 - Variables |
| `test-proj6` | Test project 6 - Artifacts |
| `test-proj7` | Test project 7 - Services |
| `test-proj8` | Test project 8 - Rules/Conditions |
| `test-proj9` | Test project 9 - Cache |
| `test-proj10` | Test project 10 - Hooks |
| `test-proj11` | Test project 11 - Includes |
| `test-proj12` | Test project 12 - YAML Anchors |
| `test-proj13` | Test project 13 - Extends |
| `test-proj14` | Test project 14 - Retry/Timeout |
| `test-proj15` | Test project 15 - Reports/Coverage |
| `test-proj16` | Test project 16 - Child Pipelines |
| `test-proj17` | Test project 17 - Matrix/Parallel |
| `test-proj18` | Test project 18 - Resource Groups |
| `test-proj19` | Test project 19 - Complex DAG |
| `test-proj20` | Test project 20 - Kitchen Sink |
| `e2e` | Diff all projects against their golden outputs |
| `e2e-update` | Regenerate the golden outputs |

## Project-Level Recipes

Each project's justfile includes:

### lint
Validates the `.gitlab-ci.yml` file for syntax and semantic errors.

**Usage:**
```bash
cd test_ci_projects/proj1
just lint
```

**Expected output:**
- Success: "GitLab CI configuration is valid"
- Failure: List of validation errors

### dag
Generates a Graphviz DOT format representation of the pipeline DAG.

**Usage:**
```bash
cd test_ci_projects/proj4
just dag
```

**Expected output:**
- DOT format output to stdout
- Can be piped to `dot` for visualization: `just dag | dot -Tpng -o dag.png`

### dry-run
Simulates pipeline execution with runner assignment and job scheduling.

**Usage:**
```bash
cd test_ci_projects/proj3
just dry-run
```

**Expected output:**
- Timeline of job assignments
- Runner assignment messages
- Final pipeline status

### test
Runs all three commands in sequence (lint, dag, dry-run).

**Usage:**
```bash
cd test_ci_projects/proj1
just test
```

**Expected output:**
- Output from lint command
- Output from dag command
- Output from dry-run command
- Success message: "All tests completed successfully"

## Testing Strategy

### Progressive Testing

Test projects in order of complexity:

**Level 1 - Basic (proj1-3):**
```bash
just test-proj1
just test-proj2
just test-proj3
```

**Level 2 - Intermediate (proj4-10):**
```bash
for i in 4 5 6 7 8 9 10; do just test-proj$i; done
```

**Level 3 - Advanced (proj11-15):**
```bash
for i in 11 12 13 14 15; do just test-proj$i; done
```

**Level 4 - Complex (proj16-19):**
```bash
for i in 16 17 18 19; do just test-proj$i; done
```

**Level 5 - Comprehensive (proj20):**
```bash
just test-proj20
```

### Feature-Specific Testing

Test specific features:

**DAG and Needs:**
```bash
just test-proj4   # Basic needs
just test-proj19  # Complex DAG
```

**Variables:**
```bash
just test-proj5   # Variable handling
```

**Artifacts:**
```bash
just test-proj6   # Artifact passing
```

**Includes:**
```bash
just test-proj11  # File inclusion
```

**Child Pipelines:**
```bash
just test-proj16  # Parent/child pipelines
```

**Matrix:**
```bash
just test-proj17  # Matrix expansion
```

## Expected Behavior

### Successful Test Run

When a test passes, you should see:
1. **Lint**: "GitLab CI configuration is valid"
2. **DAG**: Valid Graphviz DOT output
3. **Dry-run**: Job assignment timeline with "Pipeline completed: success"
4. **Final message**: "All tests completed successfully"

### Failed Test Run

When a test fails, you should see:
1. **Lint errors**: Specific validation error messages
2. **DAG errors**: Circular dependency errors or invalid config
3. **Dry-run errors**: Missing files, invalid runner configs, or simulation failures

## Troubleshooting

### "just: command not found"

Enter the nix-shell first:
```bash
nix-shell
just test-proj1
```

### "gitlab_ci_cli: command not found"

Ensure you're running from the correct directory and the CLI binary exists:
```bash
ls -la bin/gitlab_ci_cli
# Should show executable file
```

### "Cannot find .gitlab-ci.yml"

Verify you're in the correct directory:
```bash
cd test_ci_projects/proj1
ls -la .gitlab-ci.yml
```

### GitLab Dependencies Not Installed

If you see errors about missing GitLab classes:
```bash
cd gitlab
bundle install
cd ..
```

## CI/CD Integration

These justfiles can be used in CI/CD pipelines:

```yaml
# Example GitLab CI job
test_proj1:
  script:
    - just test-proj1

test_all:
  script:
    - just e2e
```

## Automation

### Parallel Testing (Future)

Test multiple projects in parallel:
```bash
# Example with GNU parallel
parallel just ::: test-proj{1..20}
```

### Watch Mode (Future)

Auto-test on file changes:
```bash
# Example with watchexec
watchexec -w test_ci_projects/proj1/.gitlab-ci.yml "just test-proj1"
```

## Development Workflow

Typical workflow when developing a feature:

1. **Modify CLI code** (e.g., improve DAG algorithm)
2. **Test with simple project**: `just test-proj1`
3. **Test with feature-specific project**: `just test-proj4` (for DAG)
4. **Test comprehensive project**: `just test-proj20`
5. **Run full test suite**: `just e2e`

## Performance Benchmarking

Use the test projects for performance testing:

```bash
# Time individual project
time just test-proj1

# Time all projects
time just e2e

# Profile specific command
time just test-proj20  # Most complex
```

## Contributing

When adding new test projects:

1. Create project directory: `test_ci_projects/proj21/`
2. Add `.gitlab-ci.yml` with test configuration
3. Copy justfile from existing project and update project number
4. Add `test-proj21` recipe to root justfile
5. Run `just e2e-update` to create `proj21.output_reference/`, review it, commit it
6. Update documentation

## Summary

- **20 justfiles** created (one per project)
- **21 new recipes** in root justfile (20 projects + test-all)
- **4 recipes per project** (lint, dag, dry-run, test)
- **Total: 101 recipes** (80 project recipes + 21 root recipes)

All test projects are now easily testable with consistent commands!
