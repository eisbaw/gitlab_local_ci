# gitlab_ci_cli

Local GitLab CI Pipeline Simulator - Standalone, Fast, Zero Dependencies

## Description

`gitlab_ci_cli` is a command-line tool that enables developers to simulate GitLab CI/CD pipelines locally. It provides dry-run execution, DAG visualization, and comprehensive linting capabilities **without requiring a GitLab server, GitLab gems, or actual job execution**.

The tool uses **pure Ruby + YAML parsing** for standalone validation and simulation, making it fast (8-12x faster than GitLab-based validation), portable, and dependency-free.

## Key Features

- **Standalone validation**: Zero external dependencies beyond Ruby stdlib
- **Fast execution**: 0.3s validation vs 3s+ with GitLab gems
- **DAG visualization**: Generate Graphviz representations of pipeline dependencies
- **Local pipeline simulation**: Execute `.gitlab-ci.yml` files locally without a GitLab server
- **Comprehensive linting**: Validates YAML syntax, structure, and semantics
- **Runner fleet simulation**: Simulate job scheduling against mock runner fleets
- **Multiple output formats**: Support for text, JSON, and JUnit output formats
- **Zero installation time**: No gem compilation, no native dependencies

## Prerequisites

- **Nix** package manager for reproducible dependency management
- Ruby 3.0+ (managed via Nix)
- Graphviz (optional, for DAG visualization, managed via Nix)
- Just command runner (optional, for workflow automation, managed via Nix)

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd gitlab_ci_cli
   ```

2. Enter the Nix shell environment (provides all required dependencies):
   ```bash
   nix-shell
   ```

3. Verify installation:
   ```bash
   ./bin/gitlab_ci_cli --help
   ```

That's it! No gem installation, no compilation, no waiting.

## Quick Start

### Basic Workflow

1. **Validate your CI configuration:**
   ```bash
   cd your-project/
   gitlab_ci_cli lint --entry .gitlab-ci.yml
   ```

2. **Visualize pipeline dependencies:**
   ```bash
   gitlab_ci_cli dag --entry .gitlab-ci.yml | dot -Tpng -o pipeline.png
   ```

3. **Simulate pipeline execution:**
   ```bash
   gitlab_ci_cli dry-run --entry .gitlab-ci.yml --runners ./runners/
   ```

## Usage Examples

### Lint Command

Validate `.gitlab-ci.yml` syntax and semantics:

```bash
# Basic validation
gitlab_ci_cli lint --entry .gitlab-ci.yml

# JSON output format
gitlab_ci_cli lint --entry .gitlab-ci.yml --format json

# JUnit XML output (useful for CI integration)
gitlab_ci_cli lint --entry .gitlab-ci.yml --format junit
```

**Example output:**
```
GitLab CI configuration is valid
Stages: build, test, deploy
Jobs: 8
```

**What lint validates:**
- ✅ YAML syntax errors
- ✅ Job structure (script, stage, needs, extends)
- ✅ Stage references
- ✅ Needs dependencies (circular dependency detection)
- ✅ Extends references
- ⚠️  Non-standard keywords (warnings)

**What lint does NOT validate:**
- ❌ Advanced `rules:` expressions
- ❌ Include file processing (coming soon)
- ❌ Complex variable expansions
- ❌ GitLab-specific API integrations

### DAG Command

Generate Graphviz DOT representation of pipeline DAG:

```bash
# Output DOT format to stdout
gitlab_ci_cli dag --entry .gitlab-ci.yml

# Generate PNG image
gitlab_ci_cli dag --entry .gitlab-ci.yml | dot -Tpng -o pipeline.png

# Generate SVG image
gitlab_ci_cli dag --entry .gitlab-ci.yml | dot -Tsvg -o pipeline.svg
```

The DAG visualization shows:
- Job grouping by stages
- Dependencies defined via `needs` keyword
- Execution order and parallelism opportunities

### Dry-Run Command

Simulate pipeline execution against mock runner fleet:

```bash
# Basic dry-run
gitlab_ci_cli dry-run --entry .gitlab-ci.yml --runners ./runners/

# With custom variables
gitlab_ci_cli dry-run --entry .gitlab-ci.yml \
  --variables ENVIRONMENT=staging \
  --variables DEPLOY_TOKEN=$TOKEN

# Simulate specific git reference
gitlab_ci_cli dry-run --entry .gitlab-ci.yml --ref feature/my-branch
```

**Example output:**
```
Pipeline #1 created with 12 jobs

[T+0s] Job 'build-frontend' → Runner 'runner_001'
[T+0s] Job 'build-backend' → Runner 'runner_001'
[T+5s] Job 'build-frontend' completed
[T+5s] Job 'build-backend' completed
[T+6s] Job 'test-unit' → Runner 'runner_001'
...
Simulation completed at T+30s
Pipeline status: success
```

## CLI Reference

### Common Options

```
--entry FILE      Path to CI config (default: ./.gitlab-ci.yml)
--gitlab-dir DIR  Path to GitLab submodule (not used, kept for compatibility)
--runners DIR     Runner fleet directory (default: ./runners)
--ref REF         Git ref to simulate (default: HEAD)
--variables K=V   Set CI variables (can be repeated)
--format FORMAT   Output format: text|json|junit (default: text)
--help            Show help message
--version         Show version information
```

### Commands

```
lint              Validate .gitlab-ci.yml syntax and semantics
dag               Generate Graphviz DOT of pipeline DAG
dry-run           Simulate pipeline execution against mock fleet
help              Show help message
```

## Development Workflow with Justfile

The project includes a `justfile` with convenient commands:

```bash
# Show all available commands
just help

# Run tests
just test

# Run specific test file
just test-file spec/unit/lint_command_spec.rb

# Lint a YAML file
just lint

# Generate DAG visualization
just dag

# Dry run simulation
just dry-run

# Clean temporary files
just clean
```

## Architecture Overview

The tool uses a **three-module standalone design**:

### 1. Commands Module
- **lint_command.rb**: Pure Ruby YAML validation (450 lines)
  - Validates syntax, structure, and semantics
  - Circular dependency detection via DFS
  - No GitLab dependencies

- **dag_command.rb**: Graphviz DOT generation (320 lines)
  - Parses YAML, builds pipeline structure
  - Generates stage-grouped DAG visualization

- **dry_run_command.rb**: Pipeline simulation (326 lines)
  - Time-based job scheduling
  - Runner assignment and capacity tracking

### 2. Mock Server
- **mock_server.rb**: Standalone pipeline creation (290 lines)
  - Direct YAML parsing (no GitLab classes)
  - Job extraction and validation
  - Event-driven architecture

### 3. Runner Fleet Manager
- **runner_fleet.rb**: Runner loading and matching
  - JSON configuration parsing
  - Tag-based job assignment
  - Capacity tracking

**Performance:**
- Cold start: ~0.3 seconds
- Warm start: ~0.3 seconds
- Memory: Minimal (no Rails overhead)
- Gem dependencies: **Zero** (only Ruby stdlib)

## Runner Fleet Configuration

Runners are defined as JSON files in the `runners/` directory:

```json
{
  "id": "runner-1",
  "tags": ["docker", "linux"],
  "executor": "shell",
  "max_jobs": 2
}
```

Example configurations provided in `runners/`.

## Test Projects

The repository includes 20 test projects (`test_ci_projects/proj1` through `proj20`) demonstrating progressively complex GitLab CI features:

```bash
# Test a specific project
just test-proj1   # Minimal config
just test-proj4   # Needs/DAG
just test-proj19  # Complex 21-job DAG

# Test all projects
just test-all-projects
```

See `test_ci_projects/TESTING.md` for details.

## Troubleshooting

### Common Issues

**Issue: Command not found**
```bash
# Solution: Enter nix-shell
nix-shell
```

**Issue: YAML syntax error**
```
Error: YAML syntax error: mapping values are not allowed...
```
Check your YAML for unquoted strings with special characters.

**Issue: Circular dependency detected**
```
Error: Circular dependency detected involving job 'test'
```
Check your `needs:` dependencies for cycles:
```bash
gitlab_ci_cli dag --entry .gitlab-ci.yml  # Visualize dependencies
```

**Issue: Job references undefined stage**
```
Error: Job 'deploy' references undefined stage 'production'
```
Add the stage to your `stages:` list or remove the invalid stage reference.

## Performance Comparison

| Metric | With GitLab Gems | Standalone (Current) |
|--------|-----------------|---------------------|
| Cold start time | 2.5-3.5s | 0.3s |
| Gem install time | 5-10 minutes | 0s |
| Dependencies | 697 gems | 0 gems |
| Native compilation | Required | None |
| Memory usage | High (Rails) | Low (pure Ruby) |

## Validation Coverage

| Feature | Validated | Notes |
|---------|-----------|-------|
| YAML syntax | ✅ | Via Psych parser |
| Job structure | ✅ | Required fields, formats |
| Stage references | ✅ | Validates stages exist |
| Needs dependencies | ✅ | Circular detection |
| Extends references | ✅ | Validates templates exist |
| Script format | ✅ | Array or string |
| Include files | ❌ | Future enhancement |
| Rules expressions | ❌ | GitLab-specific |
| Variable expansion | ❌ | Coming soon |

## Documentation

- **README.md** (this file): Main entry point and usage guide
- **arch.md**: Detailed architecture and design decisions
- **CONTRIBUTING.md**: Development guidelines and workflow
- **CHANGELOG.md**: Version history and changes
- **REFACTORING_RESULTS.md**: Standalone refactoring summary
- **docs/event_schema.md**: Event system reference
- **docs/runner_format.md**: Runner configuration format
- **test_ci_projects/TESTING.md**: Test project guide

## License

Apache License 2.0

Copyright 2025 gitlab_ci_cli contributors

See LICENSE file for full text.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development setup
- Running tests
- Code style guidelines
- Submitting pull requests

## Primary Use Cases

- **Pre-commit validation**: Validate `.gitlab-ci.yml` before pushing
- **Pipeline debugging**: Visualize job dependencies and execution order
- **Runner capacity planning**: Simulate job scheduling against mock fleets
- **CI/CD education**: Learn GitLab CI behavior without server infrastructure
- **Fast feedback loops**: 0.3s validation vs waiting for GitLab server

## Acknowledgments

Built with MPED architectural principles: Minimal dependencies, Pragmatic design, Effective development, Data-driven decisions.

Inspired by the need for fast, local GitLab CI validation without heavyweight dependencies.
