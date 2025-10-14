# gitlab_ci_cli

Local GitLab CI Pipeline Simulator

## Description

`gitlab_ci_cli` is a command-line tool that enables developers to simulate GitLab CI/CD pipelines locally by reusing the actual GitLab source code as a git submodule. It provides dry-run execution, DAG visualization, and comprehensive linting capabilities without requiring a GitLab server or actual job execution.

The tool follows a zero-patch policy, importing GitLab as an unmodified git submodule to maintain upstream compatibility and uses an event capture architecture to intercept runner communication events rather than reimplementing logic.

## Key Features

- **Local pipeline simulation**: Execute `.gitlab-ci.yml` files locally without a GitLab server
- **DAG visualization and linting**: Generate Graphviz representations and validate YAML using GitLab's own validators
- **Zero patching**: Use GitLab as an unmodified submodule for easy upstream tracking
- **Extensible architecture**: Enable future replacement of mock components with real executors
- **Variable handling**: Support for CI variables with configurable undefined variable handling (warning/error/empty modes)
- **Runner fleet simulation**: Simulate job scheduling against mock runner fleets for capacity planning
- **Multiple output formats**: Support for text, JSON, and JUnit output formats

## Prerequisites

- **Nix** package manager for reproducible dependency management
- Git 2.25+ (managed via Nix)
- Ruby 3.0+ (managed via Nix)
- Bundler (managed via Nix)
- Graphviz (optional, for DAG visualization, managed via Nix)
- Just command runner (optional, for workflow automation, managed via Nix)

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd gitlab_ci_cli
   ```

2. Enter the Nix shell environment (this provides all required dependencies):
   ```bash
   nix-shell
   ```

3. Initialize the GitLab submodule and install Ruby dependencies:
   ```bash
   git submodule update --init
   bundle install
   ```

4. Verify installation:
   ```bash
   ./bin/gitlab_ci_cli --help
   ```

## Quick Start

### Basic Workflow

1. **Validate your CI configuration:**
   ```bash
   cd your-project/
   gitlab_ci_cli lint
   ```

2. **Visualize pipeline dependencies:**
   ```bash
   gitlab_ci_cli dag | dot -Tpng -o pipeline.png
   ```

3. **Simulate pipeline execution:**
   ```bash
   gitlab_ci_cli dry-run --env DEPLOY_ENV=staging
   ```

4. **Debug undefined variables:**
   ```bash
   gitlab_ci_cli dry-run --undefined=error
   ```

## Usage Examples

### Lint Command

Validate `.gitlab-ci.yml` syntax and semantics:

```bash
# Basic validation
gitlab_ci_cli lint

# Validate specific file
gitlab_ci_cli lint --entry path/to/.gitlab-ci.yml

# JSON output format
gitlab_ci_cli lint --format json

# JUnit XML output (useful for CI integration)
gitlab_ci_cli lint --format junit
```

**Example output:**
```
✓ Configuration is valid
  Stages: build → test → deploy
  Jobs: 8
```

### DAG Command

Generate Graphviz DOT representation of pipeline DAG:

```bash
# Output DOT format to stdout
gitlab_ci_cli dag

# Generate PNG image
gitlab_ci_cli dag | dot -Tpng -o pipeline.png

# Generate SVG image
gitlab_ci_cli dag | dot -Tsvg -o pipeline.svg

# Visualize specific file
gitlab_ci_cli dag --entry path/to/.gitlab-ci.yml
```

The DAG visualization shows:
- Job grouping by stages
- Dependencies defined via `needs` keyword
- Execution order and parallelism opportunities

### Dry-Run Command

Simulate pipeline execution against mock runner fleet:

```bash
# Basic dry-run
gitlab_ci_cli dry-run

# With custom variables
gitlab_ci_cli dry-run \
  --variables ENVIRONMENT=staging \
  --variables DEPLOY_TOKEN=$TOKEN

# Specify runner fleet directory
gitlab_ci_cli dry-run --runners ./custom-runners/

# Fail on undefined variables
gitlab_ci_cli dry-run --undefined=error

# Warn on undefined variables (default)
gitlab_ci_cli dry-run --undefined=warning

# Replace undefined variables with empty string
gitlab_ci_cli dry-run --undefined=empty

# Simulate specific git reference
gitlab_ci_cli dry-run --ref feature/my-branch

# Simulate specific pipeline type
gitlab_ci_cli dry-run --pipeline merge_request
```

**Example output:**
```
Pipeline #1 created with 12 jobs

[T+0s] Job 'build-frontend' → Runner 'docker-runner-01'
[T+0s] Job 'build-backend' → Runner 'docker-runner-02'
[T+1s] Job 'test-unit' → Runner 'docker-runner-01'
[T+2s] Job 'test-integration' waiting (no eligible runner)
...
Pipeline completed: success
```

## CLI Flags Documentation

### Global Options

```
--entry FILE      Path to CI config (default: ./.gitlab-ci.yml)
--project DIR     Project directory (default: current directory)
--runners DIR     Runner fleet directory (default: ./runners)
--ref REF         Git ref to simulate (default: HEAD)
--pipeline TYPE   Pipeline type: push|merge_request|schedule|manual
--variables K=V   Set CI variables (can be repeated)
--env K=V         Set environment variables (alias for --variables)
--undefined MODE  Handle undefined vars: warning|error|empty (default: warning)
--verbose         Increase output verbosity
--format FORMAT   Output format: text|json|junit (default: text)
--gitlab-dir DIR  Path to GitLab submodule (default: ./gitlab)
--help            Show help message
--version         Show version information
```

### Commands

```
lint              Validate .gitlab-ci.yml syntax and semantics
dag               Generate Graphviz DOT of pipeline DAG
dry-run          Simulate pipeline execution against mock fleet
help              Show help message
```

## Development Workflow with Justfile

The project includes a `justfile` with convenient aliases:

```bash
# Show all available commands
just help

# Enter nix-shell
just shell

# Initialize setup
just setup

# Run tests
just test

# Run specific test file
just test-file spec/unit/mock_server_spec.rb

# Lint YAML file
just lint

# Generate DAG visualization
just dag

# Dry run simulation
just dry-run

# Update GitLab submodule
just update-gitlab

# Clean temporary files
just clean

# Run integration tests
just test-integration
```

## GitLab Version Compatibility

| GitLab Version | Status | Notes |
|---------------|--------|-------|
| 17.x | Supported | Latest stable version |
| 16.x | Supported | Long-term support |
| 15.x | Supported | Minimum supported version |
| < 15.0 | Not supported | Older versions may work but are untested |

The GitLab submodule is pinned to a specific version. To update:

```bash
just update-gitlab
```

Or manually:

```bash
cd gitlab
git fetch
git checkout <desired-tag>
cd ..
git add gitlab
git commit -m "Update GitLab submodule to <version>"
```

## Architecture Overview

The tool uses a three-module design:

1. **Module 1: Mock GitLab Server**
   - Parses `.gitlab-ci.yml` using upstream `Gitlab::Ci::YamlProcessor`
   - Constructs pipeline DAG using upstream GitLab services
   - Schedules jobs and emits events

2. **Module 2: Runner Fleet Manager**
   - Loads runner configurations from JSON files
   - Matches jobs to eligible runners based on tags
   - Tracks runner capacity and availability

3. **Module 3: Mock Runner Client**
   - Receives job assignments via events
   - Logs job details (script, image, services, artifacts)
   - Simulates job state transitions

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

Example runner configurations are provided in `runners/`.

## Troubleshooting

### Common Issues

**Issue: GitLab submodule not initialized**
```bash
# Solution:
git submodule update --init
```

**Issue: Ruby dependencies not installed**
```bash
# Solution:
bundle install
```

**Issue: Nix environment not active**
```bash
# Solution:
nix-shell
```

**Issue: Circular dependency detected**
```
Error: Circular dependency detected in pipeline
```
Check your `needs` dependencies for cycles using the DAG command.

**Issue: Undefined variable warnings**
```
Warning: Undefined variable 'DEPLOY_TOKEN'
```
Use `--undefined=error` to fail fast or define the variable with `--variables DEPLOY_TOKEN=value`.

## License

Apache License 2.0

Copyright 2025 gitlab_ci_cli contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:

- Development setup
- Running tests
- Code style guidelines
- Submitting pull requests
- Updating the GitLab submodule

## Primary Use Cases

- **Pre-commit validation**: Validate `.gitlab-ci.yml` before pushing
- **Pipeline debugging**: Visualize job dependencies and execution order
- **Runner capacity planning**: Simulate job scheduling against mock runner fleets
- **CI/CD education**: Learn GitLab CI behavior without server infrastructure
