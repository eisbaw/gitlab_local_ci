# Architecture Documentation

## Overview

`gitlab_ci_cli` is a standalone command-line tool for simulating GitLab CI/CD pipelines locally. The architecture follows MPED principles (Minimal dependencies, Pragmatic design, Effective development, Data-driven decisions) with a focus on simplicity, composability, and hackability.

## Design Principles

### 1. Minimal Dependencies
- **Zero external gems**: Uses only Ruby standard library
- **No GitLab code dependencies**: Standalone YAML parsing and validation
- **Fast startup**: ~0.3s cold start time
- **No compilation**: No native extensions or C gems

### 2. Fail-Fast Error Handling
- Input validation at entry points
- Early return on validation failures
- Clear, actionable error messages
- No silent failures or warnings ignored

### 3. Composable Architecture
- Independent modules with clear responsibilities
- Event-driven communication between components
- Pluggable formatters for output customization
- Extensible command system

### 4. Data-Driven Design
- Configuration as pure data (JSON files for runners)
- Immutable pipeline objects
- State machines for job lifecycle
- Event logs for observability

## System Architecture

### Three-Module Design

```
┌─────────────────────────────────────────────────────────┐
│                     gitlab_ci_cli                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Module 1: Commands                               │  │
│  │  - LintCommand: Validation logic                 │  │
│  │  - DagCommand: Dependency graph generation       │  │
│  │  - DryRunCommand: Pipeline simulation            │  │
│  └────────────────┬─────────────────────────────────┘  │
│                   │                                     │
│                   ▼                                     │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Module 2: Mock Server                            │  │
│  │  - Pipeline creation and validation              │  │
│  │  - Job extraction and state management           │  │
│  │  - Event emission infrastructure                 │  │
│  └────────────────┬─────────────────────────────────┘  │
│                   │                                     │
│                   ▼                                     │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Module 3: Runner Fleet                           │  │
│  │  - Runner configuration loading                  │  │
│  │  - Tag-based job matching                        │  │
│  │  - Capacity tracking and assignment              │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Module Details

### Module 1: Commands

The commands module provides the CLI interface and orchestrates the execution of each command.

#### Components

**LintCommand** (`lib/commands/lint_command.rb`)
- Validates YAML syntax using Ruby's Psych parser
- Validates job structure and required fields
- Detects circular dependencies in DAG
- Validates stage references
- Validates extends references

**DagCommand** (`lib/commands/dag_command.rb`)
- Parses YAML configuration
- Builds pipeline structure
- Generates Graphviz DOT output
- Groups jobs by stages
- Visualizes needs dependencies

**DryRunCommand** (`lib/commands/dry_run_command.rb`)
- Simulates pipeline execution
- Time-based job scheduling
- Runner assignment and capacity management
- Event-driven job lifecycle
- Output formatting and timeline visualization

#### Design Patterns

- **Command Pattern**: Each command is a self-contained class with an `execute` method
- **Result Objects**: Commands return result objects with success/failure status
- **Formatter Pattern**: Output formatting is delegated to formatter classes

### Module 2: Mock Server

The mock server creates and manages pipeline state without requiring actual GitLab infrastructure.

#### Components

**MockServer** (`lib/mock_server.rb`)
- YAML parsing and validation
- Pipeline object creation
- Job extraction from configuration
- Event emission for observability
- State transition management

**MockJob** (`lib/mock_job.rb`)
- Job state machine (pending → running → completed/failed)
- Immutable job configuration
- Attribute accessors for job properties
- State validation and transition rules

**VariableExpander** (`lib/variable_expander.rb`)
- Variable substitution in job scripts and configuration
- Multiple handling modes (warning, error, empty)
- Support for ${VAR} and $VAR syntax
- Recursive expansion with cycle detection

**IncludeProcessor** (`lib/include_processor.rb`)
- Processes GitLab CI include directives
- Supports local, remote, template, and project includes
- Circular include detection
- Depth limiting (max 150)
- Deep merge of configurations

**ChildPipelineHandler** (`lib/child_pipeline_handler.rb`)
- Handles trigger jobs for child pipelines
- Variable inheritance from parent
- Recursive pipeline invocation
- Depth limiting (max 10)
- Exit code propagation

#### Event System

Events are emitted at key points in pipeline execution:

- `pipeline_created`: Pipeline successfully created
- `pipeline_started`: Pipeline begins execution
- `pipeline_completed`: Pipeline finished (success/failure)
- `job_assigned`: Job assigned to runner
- `job_started`: Job execution begins
- `job_completed`: Job execution finishes
- `child_pipeline_created`: Child pipeline triggered

Events include:
- Event type
- Timestamp
- Job/pipeline ID
- Relevant metadata

See [event_schema.md](event_schema.md) for detailed event structure.

### Module 3: Runner Fleet

The runner fleet manages mock runners and handles job-to-runner assignment.

#### Components

**RunnerFleet** (`lib/runner_fleet.rb`)
- Loads runner configurations from JSON files
- Maintains list of available runners
- Finds eligible runners for jobs
- Tracks runner capacity

**MockRunner** (`lib/mock_runner.rb`)
- Runner configuration and properties
- Tag matching logic
- Capacity tracking (running_jobs vs max_jobs)
- Job assignment and release

**RunnerExporter** (`lib/runner_exporter.rb`)
- Exports runner configurations from live GitLab instances
- GitLab API client integration
- Pagination handling for large fleets
- JSON output formatting
- Error handling for network/auth issues

#### Runner Matching Algorithm

```ruby
def find_available_runner(job)
  @runners.find do |runner|
    runner.can_handle?(job) &&  # Tag matching
    runner.has_capacity?         # Not at max_jobs
  end
end
```

Tag matching:
1. If job has no tags and runner has `run_untagged: true` → match
2. If job tags are subset of runner tags → match
3. Otherwise → no match

Capacity check:
1. `running_jobs < max_jobs` → has capacity
2. Otherwise → no capacity

See [runner_format.md](runner_format.md) for configuration details.

## Data Flow

### Lint Command Flow

```
User Input (.gitlab-ci.yml)
    ↓
YAML Parser (Psych)
    ↓
LintCommand.execute
    ↓
  ├─→ Validate YAML syntax
  ├─→ Validate job structure
  ├─→ Detect circular dependencies
  ├─→ Validate stage references
  └─→ Validate extends references
    ↓
Result Object
    ↓
Formatter (Text/JSON/JUnit)
    ↓
Output to User
```

### DAG Command Flow

```
User Input (.gitlab-ci.yml)
    ↓
YAML Parser
    ↓
DagCommand.execute
    ↓
  ├─→ Build pipeline structure
  ├─→ Extract stages
  ├─→ Extract jobs with needs
  └─→ Build dependency graph
    ↓
Graphviz DOT Generation
    ↓
  ├─→ Stage subgraphs
  ├─→ Job nodes
  └─→ Dependency edges
    ↓
Output DOT to stdout
```

### Dry-Run Command Flow

```
User Input (.gitlab-ci.yml + runners/)
    ↓
YAML Parser + Runner Loading
    ↓
DryRunCommand.execute
    ↓
MockServer.create_pipeline
    ↓
┌─────────────────────────────┐
│ Main Scheduling Loop        │
│                             │
│  while has_pending_jobs?    │
│    process_pipeline()       │
│                             │
│    for each pending job:    │
│      find_available_runner  │
│      if runner found:       │
│        assign_job           │
│        transition_to :running│
│      else:                  │
│        log "waiting"        │
│                             │
│    increment time           │
└─────────────────────────────┘
    ↓
Output timeline
```

## Performance Characteristics

### Benchmarks

**Pipeline Creation Performance:**
- 100-job pipeline: 0.45ms
- 1000-job pipeline: 5.29ms
- Complex DAG: 0.43ms

**Runner Fleet Performance:**
- Load 10 runners: 2.34ms
- Load 100 runners: 1.4ms
- Runner lookup (100 runners): 0.0004ms
- Job assignment rate: 6,412 jobs/sec

**Memory Usage:**
- Cold start: Minimal (no Rails overhead)
- 5×200-job pipelines: 1.0 MB growth
- No memory leaks detected

### Optimization Strategies

1. **Lazy Evaluation**
   - Jobs are only processed when needed
   - Runners loaded on-demand
   - Include processing deferred until required

2. **Early Exit**
   - Tag matching stops at first match
   - Validation fails fast on first error
   - DAG traversal terminates on cycle detection

3. **Efficient Data Structures**
   - Hash maps for O(1) lookups (job by name, stage by name)
   - Sets for cycle detection
   - Arrays for ordered collections (stages, jobs)

4. **Minimal Dependencies**
   - No gem loading overhead
   - No database connections
   - No HTTP requests (except include:remote)

## Error Handling

### Error Hierarchy

```
StandardError
├── ConfigurationError
│   ├── InvalidYAMLError
│   ├── CircularDependencyError
│   └── UndefinedStageError
├── ValidationError
│   ├── MissingRequiredFieldError
│   └── InvalidFieldFormatError
├── IncludeDepthExceededError
└── UndefinedVariableError
```

### Error Handling Principles

1. **Fail-Fast**: Validate inputs at entry points
2. **Clear Messages**: Include context and actionable suggestions
3. **No Silent Failures**: All errors are explicit
4. **Recoverable vs Fatal**: Distinguish between warnings and errors

### Example Error Messages

```
Error: Circular dependency detected involving job 'test'
Cycle: build → test → lint → build

Suggestion: Remove one of the 'needs' relationships to break the cycle
```

```
Error: Job 'deploy' references undefined stage 'production'
Available stages: build, test, deploy

Suggestion: Add 'production' to the stages list or change the job's stage
```

## Extensibility

### Adding New Commands

1. Create command class in `lib/commands/`
2. Implement `execute(options)` method
3. Return `Result` object with success/failure
4. Register command in CLI parser

Example:

```ruby
module Commands
  class MyCommand
    def self.execute(options)
      # Implementation
      Result.new(success: true, message: "Done")
    end
  end
end
```

### Adding New Output Formatters

1. Create formatter class in `lib/formatters/`
2. Inherit from `BaseFormatter`
3. Implement `format(result)` method
4. Register in formatter factory

Example:

```ruby
module Formatters
  class MyFormatter < BaseFormatter
    def format(result)
      # Convert result to custom format
    end
  end
end
```

### Adding New Include Types

1. Add type to `INCLUDE_TYPES` constant
2. Implement `fetch_#{type}_include` method
3. Update `determine_include_type` logic
4. Add tests

## Testing Strategy

### Test Pyramid

```
       /\
      /  \    Unit Tests (426 tests)
     /____\   - Core logic and business rules
    /      \  - No external dependencies
   /________\ Integration Tests (36 tests)
  /          \ - Full command execution
 /____________\ - End-to-end scenarios
   Benchmarks (14 tests)
   - Performance validation
   - Memory profiling
```

### Test Categories

**Unit Tests** (`spec/unit/`)
- MockServer, MockRunner, MockJob
- Commands (Lint, DAG, DryRun)
- Variable expansion and include processing
- Runner fleet and job matching
- Formatters and output generation

**Integration Tests** (`spec/integration/`)
- Full command execution
- Real YAML files from test projects
- Output format validation
- Error handling scenarios

**Benchmark Tests** (`spec/benchmarks/`)
- Pipeline creation performance
- Runner matching performance
- Memory usage validation
- Scalability testing

### Test Principles

1. **Isolation**: Unit tests don't touch filesystem or network
2. **Repeatability**: Tests are deterministic and fast
3. **Coverage**: 90%+ code coverage target
4. **Real Scenarios**: Integration tests use actual GitLab CI configs

## Security Considerations

### Input Validation

- YAML files are parsed with safe loading (`YAML.safe_load`)
- File paths are validated against directory traversal
- Variable names are validated against injection patterns
- Include URLs are validated (HTTPS-only for remote)

### No Code Execution

- Scripts are logged but never executed
- No shell evaluation of user input
- No dynamic require or eval
- No subprocess spawning (except for child pipelines)

### Data Privacy

- No data transmitted to external services
- No telemetry or tracking
- Local-only operation
- Runner configurations are local files

## Future Enhancements

### Planned Features

1. **Enhanced Include Support**
   - Component includes (GitLab 16+)
   - Better template library
   - Include caching

2. **Rules Engine**
   - Basic rules evaluation
   - Variable-based conditionals
   - Changes-based rules

3. **Variable Expansion**
   - Complex variable expressions
   - Predefined CI variables
   - File-based variables

4. **Cache and Artifact Simulation**
   - Cache key matching
   - Artifact dependencies
   - Artifact expiration

5. **Service Container Handling**
   - Service definitions
   - Service health checks
   - Network simulation

### Architecture Evolution

The current architecture supports these extensions through:
- Modular command system
- Pluggable validators
- Event-driven pipeline execution
- Extensible include processor

## Troubleshooting Guide

### Common Issues

**Issue: Slow startup**
- Check Ruby version (3.0+ recommended)
- Verify no extra gems loaded
- Profile with `time ./bin/gitlab_ci_cli --help`

**Issue: Circular dependency not detected**
- Verify needs syntax (array of strings or array of hashes)
- Check for hidden cycles through extends
- Use `dag` command to visualize

**Issue: Runner not assigned**
- Check runner tags match job tags
- Verify runner capacity (max_jobs)
- Use `--verbose` to see matching details

**Issue: Memory usage growth**
- Profile with benchmarks: `rspec spec/benchmarks/`
- Check for retained references in event queue
- Verify pipeline objects are released

## References

- [Event Schema](event_schema.md)
- [Runner Format](runner_format.md)
- [MPED Principles](https://github.com/mped)
- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
