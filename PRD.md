# Product Requirements Document: gitlab_ci_cli
## Local GitLab CI Pipeline Simulator

**Version:** 1.1  
**Date:** October 2025, status updated November 2026  
**Author:** Engineering Team  
**Status:** Implemented in part; see "Status" below

---

## Status (November 2026)

The product shipped, but not on the architecture this document first
proposed. Read sections 2 and 3 as the original design, not the current one.

- **Standalone port, not gem reuse.** Loading GitLab's own classes
  (`Gitlab::Ci::YamlProcessor`, `Ci::RegisterJobService`) needed hundreds of
  gems and a Rails environment. The tool instead ports GitLab's
  pipeline-construction rules to plain Ruby, step by step in GitLab's order,
  in one module (`lib/pipeline_builder.rb`). The `gitlab/` submodule
  (unmodified, pinned to v19.5.3-ee) is the reference those rules are ported
  and checked against, and the source of `include: template:` files. See
  [docs/architecture.md](docs/architecture.md).
- **Jobs can run.** Running jobs was a non-goal (1.4). `run <job>` now runs a
  job in `bash` on the host with GitLab's job environment, and `export-just`
  writes the jobs as `just` recipes. There is still no container, image,
  service, cache or artifact handling.
- **Network.** Everything runs locally except fetching includes that are not
  on disk (`remote`, `project`, `component`, missing templates).
- **Not yet built from this document:** `spec:inputs` and CI components
  (3.5.3), the `--undefined` modes (3.5.1), runner export as a command
  (3.2.3), and testing against several GitLab versions (6.2).

---

## 1. Executive Summary

### 1.1 Product Vision
`gitlab_ci_cli` is a command-line tool that enables developers to simulate GitLab CI/CD pipelines locally, following GitLab's own rules for building a pipeline (ported from the GitLab source, which is pinned as a git submodule). It provides linting, DAG visualization, dry-run scheduling on a mock runner fleet, local execution of single jobs, and export of jobs as `just` recipes, without requiring a GitLab server.

### 1.2 Key Principles
- **Zero-patch policy**: Import GitLab as an unmodified git submodule to maintain upstream compatibility
- **Event capture architecture** (original design, superseded): Intercept runner communication events rather than reimplementing logic. Implemented instead: a standalone port of GitLab's pipeline construction, checked against the pinned source
- **Ruby-native**: Written in Ruby, so GitLab's Ruby logic can be ported closely and its source read directly
- **Local-first**: All operations run locally; the network is used only to fetch includes that are not on disk

### 1.3 Goals
- **Local pipeline simulation**: Execute `.gitlab-ci.yml` files locally without a GitLab server
- **DAG visualization and linting**: Generate Graphviz representations and validate YAML using GitLab's own validators
- **Zero patching**: Use GitLab as an unmodified submodule for easy upstream tracking
- **Extensible architecture**: Enable future replacement of mock components with real executors

### 1.4 Non-Goals
- Implementing artifact uploads, container/image execution, or networked API endpoints (single jobs can run locally with `run`, see Status)
- Providing full UI parity with GitLab's web interface
- Persisting pipeline state beyond in-memory simulation
- Dynamic runner registration or auto-scaling

### 1.5 Assumptions
- Users have Nix installed for reproducible dependency management
- All dependencies (Ruby 3.3, Git, Graphviz, just) are managed via Nix (`flake.nix`, `nix develop`; `shell.nix` also works)
- The GitLab submodule (a checkout of a release tag) is acceptable as a development dependency; the packaged CLI does not need it except for `include: template:`
- Runners are represented by static JSON files
- (Original assumption, not borne out: direct reuse of upstream modules like `Gitlab::Ci::YamlProcessor`; see Status)

### 1.6 Primary Use Cases
1. **Pre-commit validation**: Developers validate `.gitlab-ci.yml` before pushing
2. **Pipeline debugging**: Visualize job dependencies and execution order
3. **Runner capacity planning**: Simulate job scheduling against mock runner fleets
4. **CI/CD education**: Learn GitLab CI behavior without server infrastructure

---

## 2. Architecture Overview

> Sections 2 and 3 describe the original design (reuse of GitLab classes,
> three mock modules). The implemented architecture is in
> [docs/architecture.md](docs/architecture.md); the current CLI is in
> [docs/usage.md](docs/usage.md).

### 2.1 Three-Module Design

```
┌─────────────────────────────────────────────────────────────┐
│                        gitlab_ci_cli                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────┐                                   │
│  │  Module 1:           │                                   │
│  │  Mock GitLab Server  │                                   │
│  │  - YAML Parsing      │                                   │
│  │  - DAG Construction  │                                   │
│  │  - Pipeline Logic    │                                   │
│  │  - Job Scheduler     │                                   │
│  └──────────┬──────────┘                                   │
│             │                                               │
│             ▼                                               │
│  ┌─────────────────────┐         ┌────────────────────┐    │
│  │  Module 2:           │◄────────┤  runners/          │    │
│  │  Runner Fleet        │         │  - runner1.json    │    │
│  │  Manager             │         │  - runner2.json    │    │
│  │                      │         │  - ...             │    │
│  └──────────┬──────────┘         └────────────────────┘    │
│             │                                               │
│             ▼                                               │
│  ┌─────────────────────┐                                   │
│  │  Module 3:           │                                   │
│  │  Mock Runner Client  │                                   │
│  │  - Job Receipt       │                                   │
│  │  - Event Logging     │                                   │
│  └─────────────────────┘                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Git Submodule Strategy

```
gitlab_ci_cli/
├── .gitmodules              # Points to gitlab.com/gitlab-org/gitlab
├── shell.nix                # Nix environment with all dependencies
├── gitlab/                  # Unmodified GitLab CE submodule
│   ├── lib/gitlab/ci/      # Reused without modification
│   ├── app/services/ci/    # Reused without modification
│   └── ...
├── lib/
│   ├── gitlab_ci_cli.rb    # Main entry point
│   ├── mock_server.rb       # Module 1 implementation
│   ├── runner_fleet.rb      # Module 2 implementation
│   └── mock_runner.rb       # Module 3 implementation
├── spec/                    # Test suite
├── bin/
│   └── gitlab_ci_cli        # Executable
├── Gemfile                  # Ruby dependencies
└── justfile                 # Common development commands
```

### 2.3 Architecture Trade-offs

| Decision | Pros | Cons |
|----------|------|------|
| **Ruby Implementation** | Direct reuse of GitLab classes, no translation layer | Must maintain Ruby environment |
| **Git Submodule** | Zero patches, easy upstream tracking | Adds ~100MB to repository, version pinning complexity |
| **Event-Driven Runner Interface** | Decouples scheduling from execution, future extensibility | Requires modeling concurrency and job acknowledgment |
| **JSON Fleet Format** | Human-readable, easy to export from production | May not capture all runner settings |
| **In-Memory Simulation** | Fast, no external dependencies | No persistence between runs |

### 2.4 Critical Design Constraints

- **No GitLab patches**: All adaptations must be via wrapper classes or monkey-patching
- **Version pinning**: Lock GitLab submodule to specific tags for stability
- **Upstream refactoring**: Abstract interception points to minimize breakage

```
gitlab_ci_cli/
├── .gitmodules              # Points to gitlab.com/gitlab-org/gitlab
├── shell.nix                # Nix environment with all dependencies
├── gitlab/                  # Unmodified GitLab CE submodule
│   ├── lib/gitlab/ci/      # Reused without modification
│   ├── app/services/ci/    # Reused without modification
│   └── ...
├── lib/
│   ├── gitlab_ci_cli.rb    # Main entry point
│   ├── mock_server.rb       # Module 1 implementation
│   ├── runner_fleet.rb      # Module 2 implementation
│   └── mock_runner.rb       # Module 3 implementation
├── spec/                    # Test suite
├── bin/
│   └── gitlab_ci_cli        # Executable
├── Gemfile                  # Ruby dependencies
└── justfile                 # Common development commands
```

---

## 3. Functional Requirements

### 3.1 Module 1: Mock GitLab Server

#### 3.1.1 Core Responsibilities
- Parse `.gitlab-ci.yml` using upstream `Gitlab::Ci::YamlProcessor`
- Construct pipeline DAG using upstream `Ci::CreatePipelineService`
- Schedule jobs using upstream `Ci::ProcessPipelineService`
- Intercept runner API calls instead of making HTTP requests

#### 3.1.2 Event Interception Points
```ruby
# Intercept at Ci::RegisterJobService#execute
module MockServer
  class JobDispatcher
    def intercept_job_request(runner_token)
      # Original logic from Ci::RegisterJobService
      job = find_eligible_job(runner_token)
      
      # Capture event instead of HTTP response
      emit_event(:job_assigned, {
        job_id: job.id,
        runner_id: runner_token,
        job_payload: build_job_payload(job)
      })
    end
  end
end
```

#### 3.1.3 Required Upstream Classes
- `Gitlab::Ci::YamlProcessor` - YAML parsing and validation
- `Gitlab::Ci::YamlProcessor::Dag` - DAG ordering via `Dag.order` method
- `Gitlab::Ci::YamlProcessor::Result` - Provides `stages_attributes` and job needs
- `Gitlab::Ci::Config` - Configuration validation
- `Gitlab::Ci::Config::Entry::*` - Entry validators
- `Ci::CreatePipelineService` - Pipeline creation
- `Ci::ProcessPipelineService` - State transitions
- `Ci::RegisterJobService` - Job scheduling algorithm

#### 3.1.4 DAG Validation
```ruby
# Use GitLab's circular dependency detection
def validate_dag(pipeline)
  dag = Gitlab::Ci::YamlProcessor::Dag.new(pipeline.jobs)
  dag.check_circular_dependencies!
rescue Gitlab::Ci::YamlProcessor::Dag::CircularDependencyError => e
  puts "Error: Circular dependency detected: #{e.message}"
  exit 1
end
```

### 3.2 Module 2: Runner Fleet Manager

#### 3.2.1 Runner Definition Format

**Minimal Format (MVP):**
```json
{
  "id": "runner-1",
  "tags": ["docker", "linux"],
  "executor": "shell",
  "max_jobs": 2
}
```

**Extended Format (Future):**
```json
{
  "id": "runner_001",
  "description": "Docker runner on host1",
  "active": true,
  "tags": ["docker", "linux", "amd64"],
  "run_untagged": true,
  "locked": false,
  "access_level": "not_protected",
  "maximum_timeout": 3600,
  "executor": "docker",
  "executor_config": {
    "image": "alpine:latest",
    "privileged": false,
    "volumes": ["/cache"]
  },
  "concurrent": 4,
  "capacity": {
    "running_jobs": 2,
    "max_jobs": 4
  }
}
```

#### 3.2.2 Fleet Discovery
```ruby
class RunnerFleet
  def load_runners(directory = './runners')
    Dir.glob("#{directory}/*.json").map do |file|
      runner_data = JSON.parse(File.read(file))
      MockRunner.new(runner_data)
    end
  end

  def find_available_runner(job_requirements)
    @runners.find do |runner|
      runner.can_handle?(job_requirements) && 
      runner.has_capacity?
    end
  end
end
```

#### 3.2.3 GitLab Server Export Tool
```ruby
# Companion tool to export runner configs from production
class RunnerExporter
  def export_from_gitlab(gitlab_url, token)
    client = Gitlab.client(endpoint: gitlab_url, private_token: token)
    runners = client.runners(per_page: 100)
    
    runners.each do |runner|
      File.write(
        "runners/runner_#{runner.id}.json",
        runner.to_h.to_json
      )
    end
  end
end
```

### 3.3 Module 3: Mock Runner Client

#### 3.3.1 Event Handler
```ruby
class MockRunner
  def handle_job_assignment(event)
    job = event[:job_payload]
    
    puts "Runner #{@id} received job ##{job[:id]}"
    puts "  Project: #{job[:project_name]}"
    puts "  Stage: #{job[:stage]}"
    puts "  Job: #{job[:name]}"
    puts "  Script:"
    job[:script].each { |cmd| puts "    $ #{cmd}" }
    puts "  Image: #{job[:image]}"
    puts "  Services: #{job[:services].join(', ')}" if job[:services]
    puts "  Artifacts: #{job[:artifacts]}" if job[:artifacts]
    
    # Simulate state transitions
    emit_event(:job_started, job_id: job[:id])
    emit_event(:job_completed, job_id: job[:id], status: 'success')
  end
end
```

### 3.4 CLI Interface

#### 3.4.1 Command Structure
```bash
gitlab_ci_cli [OPTIONS] [COMMAND]

Commands:
  lint              Validate .gitlab-ci.yml syntax and semantics
  dag               Generate Graphviz DOT of pipeline DAG
  dry-run          Simulate pipeline execution against mock fleet
  run <job>         Execute a job locally (added after this document)
  export-just       Export jobs as justfile recipes (added after this document)
  help              Show help message

Options:
  --entry FILE      Path to CI config (default: ./.gitlab-ci.yml)
  --project DIR     Project directory (default: current directory)
  --runners DIR     Runner fleet directory (default: ./runners)
  --ref REF         Git ref to simulate (default: the checked-out branch)
  --pipeline TYPE   CI_PIPELINE_SOURCE (upstream names: push|merge_request_event|schedule|web|...)
  --variables K=V   Set CI variables (can be repeated)
  --env K=V         Set environment variables (alias for --variables)
  --undefined MODE  Handle undefined vars: warning|error|empty
  --verbose         Increase output verbosity
  --format FORMAT   Output format: text|json|junit
  --gitlab-dir DIR  Path to GitLab submodule (default: ./gitlab)
```

#### 3.4.2 Command Implementations

##### Lint Command
```ruby
def lint_command(options)
  processor = Gitlab::Ci::YamlProcessor.new(
    File.read(options[:entry]),
    project: mock_project(options),
    ref: options[:ref]
  )
  
  if processor.valid?
    puts "✓ Configuration is valid"
    puts "  Stages: #{processor.stages.join(' → ')}"
    puts "  Jobs: #{processor.jobs.count}"
  else
    puts "✗ Configuration errors:"
    processor.errors.each { |e| puts "  - #{e}" }
    exit 1
  end
end
```

##### DAG Command
```ruby
def dag_command(options)
  pipeline = create_mock_pipeline(options)
  
  puts "digraph pipeline {"
  puts '  rankdir="LR";'
  
  # Group by stages
  pipeline.stages.each do |stage|
    puts "  subgraph cluster_#{stage.name} {"
    puts "    label=\"#{stage.name}\";"
    stage.jobs.each do |job|
      puts "    #{job.name};"
    end
    puts "  }"
  end
  
  # Add needs edges
  pipeline.jobs.with_needs.each do |job|
    job.needs.each do |need|
      puts "  #{need} -> #{job.name};"
    end
  end
  
  puts "}"
end
```

##### Dry Run Command
```ruby
def dry_run_command(options)
  server = MockServer.new(gitlab_path: options[:gitlab_dir])
  fleet = RunnerFleet.load(options[:runners])

  pipeline = server.create_pipeline(
    config: File.read(options[:entry]),
    ref: options[:ref],
    variables: parse_variables(options[:variables])
  )

  puts "Pipeline ##{pipeline.id} created with #{pipeline.jobs.count} jobs"
  puts ""

  # Simulate job scheduling
  time = 0
  while pipeline.has_pending_jobs?
    server.process_pipeline(pipeline)

    pipeline.pending_jobs.each do |job|
      runner = fleet.find_available_runner(job)
      if runner
        puts "[T+#{time}s] Job '#{job.name}' → Runner '#{runner.id}'"
        runner.assign_job(job)
        job.transition_to(:running)
      else
        puts "[T+#{time}s] Job '#{job.name}' waiting (no eligible runner)"
      end
    end

    time += 1
  end

  puts ""
  puts "Pipeline completed: #{pipeline.status}"
end
```

#### 3.4.3 Justfile Workflow Commands

The justfile provides convenient aliases for common development tasks:

```makefile
# justfile - Common development workflows

# Show all available commands
help:
    @just --list

# Enter nix-shell
shell:
    nix-shell

# Initialize GitLab submodule and install dependencies
setup:
    git submodule update --init
    bundle install

# Run tests
test:
    bundle exec rspec

# Run specific test file
test-file FILE:
    bundle exec rspec {{FILE}}

# Lint YAML file
lint FILE=".gitlab-ci.yml":
    ./bin/gitlab_ci_cli lint --entry {{FILE}}

# Generate DAG visualization
dag FILE=".gitlab-ci.yml" OUTPUT="pipeline.png":
    ./bin/gitlab_ci_cli dag --entry {{FILE}} | dot -Tpng -o {{OUTPUT}}
    @echo "Generated {{OUTPUT}}"

# Dry run simulation
dry-run FILE=".gitlab-ci.yml":
    ./bin/gitlab_ci_cli dry-run --entry {{FILE}}

# Update GitLab submodule to latest version
update-gitlab:
    cd gitlab && git fetch && git checkout $(git describe --tags --abbrev=0)
    git add gitlab
    @echo "GitLab submodule updated. Review changes before committing."

# Clean temporary files
clean:
    rm -f *.png
    rm -rf tmp/

# Run integration tests
test-integration:
    bundle exec rspec spec/integration/
```

### 3.5 Advanced Features

#### 3.5.1 Variable Handling
```ruby
class VariableExpander
  def initialize(mode: :warning)
    @mode = mode # :warning, :error, :empty
  end
  
  def expand(text, variables)
    text.gsub(/\$\{?(\w+)\}?/) do |match|
      var_name = $1
      if variables.key?(var_name)
        variables[var_name]
      else
        case @mode
        when :error
          raise UndefinedVariableError, "Undefined variable: #{var_name}"
        when :warning
          warn "Warning: Undefined variable '#{var_name}'"
          match  # Keep original
        when :empty
          ""    # Replace with empty
        end
      end
    end
  end
end
```

#### 3.5.2 Child Pipeline Support
```ruby
class ChildPipelineHandler
  def trigger_child(parent_job, downstream_config)
    downstream_project = find_project(downstream_config[:project])
    
    # Recursively invoke gitlab_ci_cli
    child_process = spawn(
      "gitlab_ci_cli",
      "--entry", downstream_config[:file] || ".gitlab-ci.yml",
      "--project", downstream_project.path,
      "--variables", serialize_variables(parent_job.variables),
      "--pipeline", "parent_pipeline",
      "--parent-job-id", parent_job.id.to_s
    )
    
    Process.wait(child_process)
    
    emit_event(:child_pipeline_created, {
      parent_job: parent_job.id,
      child_project: downstream_project.name,
      status: $?.success? ? 'success' : 'failed'
    })
  end
end
```

#### 3.5.3 Include Processing
```ruby
class IncludeProcessor
  INCLUDE_TYPES = %i[local file remote template project component].freeze
  MAX_DEPTH = 150
  
  def process_includes(config, depth = 0)
    raise "Include depth exceeded" if depth > MAX_DEPTH
    
    includes = Array(config['include'])
    includes.each do |include_spec|
      content = fetch_include_content(include_spec)
      merged = deep_merge(config, YAML.safe_load(content))
      config = process_includes(merged, depth + 1)
    end
    
    config
  end
end
```

---

## 4. Non-Functional Requirements

### 4.1 Performance
- Parse and validate `.gitlab-ci.yml` files up to 1MB within 5 seconds
- Support pipelines with up to 1000 jobs
- Handle runner fleets up to 100 runners
- Complete dry-run simulation within 30 seconds for typical pipelines

### 4.2 Compatibility
- Follow the GitLab version pinned in the `gitlab/` submodule (v19.5.3-ee as of November 2026); older GitLab versions are not tested separately
- Ruby 3.3 (the version the dev shell provides and the tests run on)
- Platform support: Linux (tested); macOS and WSL expected to work but untested
- Git 2.25+ for submodule operations

### 4.3 Maintainability
- Zero patches to GitLab submodule
- Automated tests for every pipeline-construction step, and specs that compare keyword and variable lists against the pinned GitLab source
- Version pinning for GitLab submodule with documented update process
- Clear separation between mock logic and upstream code

### 4.4 Testing Strategy
```ruby
# spec/integration/yaml_processor_spec.rb
RSpec.describe "YAML Processing Integration" do
  let(:gitlab_path) { File.expand_path('../../gitlab', __dir__) }
  
  before do
    # Load upstream GitLab code
    $LOAD_PATH.unshift("#{gitlab_path}/lib")
    require 'gitlab/ci/yaml_processor'
  end
  
  it "parses basic pipeline" do
    config = <<~YAML
      stages: [build, test]
      
      build-job:
        stage: build
        script: echo "Building"
      
      test-job:
        stage: test
        needs: [build-job]
        script: echo "Testing"
    YAML
    
    processor = Gitlab::Ci::YamlProcessor.new(config)
    expect(processor).to be_valid
    expect(processor.stages).to eq(['build', 'test'])
  end
  
  it "detects circular dependencies" do
    config = <<~YAML
      job-a:
        needs: [job-b]
      job-b:
        needs: [job-a]
    YAML
    
    processor = Gitlab::Ci::YamlProcessor.new(config)
    dag = Gitlab::Ci::YamlProcessor::Dag.new(processor.jobs)
    
    expect { dag.check_circular_dependencies! }.to raise_error(
      Gitlab::Ci::YamlProcessor::Dag::CircularDependencyError
    )
  end
  
  it "validates runner tag matching" do
    runner = MockRunner.new(tags: ['docker', 'linux'])
    job = MockJob.new(tag_list: ['docker'])
    
    expect(runner.can_handle?(job)).to be true
    
    job_incompatible = MockJob.new(tag_list: ['windows'])
    expect(runner.can_handle?(job_incompatible)).to be false
  end
  
  it "enforces runner concurrency limits" do
    runner = MockRunner.new(max_jobs: 2)
    runner.assign_job(MockJob.new)
    runner.assign_job(MockJob.new)
    
    expect(runner.has_capacity?).to be false
  end
  
  it "handles undefined variables according to mode" do
    expander = VariableExpander.new(mode: :error)
    
    expect {
      expander.expand("Hello ${UNDEFINED}", {})
    }.to raise_error(UndefinedVariableError)
    
    expander_warning = VariableExpander.new(mode: :warning)
    result = expander_warning.expand("Hello ${UNDEFINED}", {})
    expect(result).to eq("Hello ${UNDEFINED}")
    
    expander_empty = VariableExpander.new(mode: :empty)
    result = expander_empty.expand("Hello ${UNDEFINED}", {})
    expect(result).to eq("Hello ")
  end
end
```

---

## 5. Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- Set up project structure with GitLab submodule
- Implement basic YAML parsing using upstream code
- Create minimal CLI with --help and --lint commands
- Establish test harness

### Phase 2: Core Simulation (Weeks 3-4)
- Implement mock server with job scheduling
- Add runner fleet loading from JSON
- Create --dry-run command with basic output
- Add integration tests

### Phase 3: Visualization (Week 5)
- Implement DAG generation with --dag command
- Add Graphviz DOT output
- Support stage and needs visualization
- Create example runner configurations

### Phase 4: Advanced Features (Weeks 6-7)
- Add variable expansion with undefined handling modes
- Implement child pipeline support
- Add include processing
- Enhance error reporting

### Phase 5: Polish (Week 8)
- Add --format options (JSON, JUnit)
- Implement runner exporter tool
- Complete documentation
- Performance optimization

---

## 6. Success Metrics

### 6.1 Functional Metrics
- 100% compatibility with GitLab CI YAML syntax
- Support for 90% of common CI patterns
- Zero false positives in linting

### 6.2 Quality Metrics
- 90% test coverage
- All integration tests passing against 3 GitLab versions
- No patches required to GitLab submodule

### 6.3 Adoption Metrics
- Successfully parse real-world `.gitlab-ci.yml` from 50 OSS projects
- Replace need for GitLab Runner in 80% of local testing scenarios
- Enable pre-commit validation in CI/CD workflows

---

## 7. Dependencies and Risks

### 7.1 Technical Dependencies
- **Nix** - Primary dependency manager (shell.nix provides reproducible environment)
- GitLab CE source code (Apache 2.0 license compatible)
- Ruby 3.3 runtime (via Nix); the CLI itself needs no gems beyond Ruby's bundled ones
- Bundler-managed gems for development only (rspec, simplecov)
- Git 2.25+ for submodule operations (via Nix)
- Graphviz (optional, for DAG visualization, via Nix)
- Just command runner (optional, for workflow automation, via Nix)

### 7.2 Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| GitLab API changes | High | Medium | Pin submodule versions, maintain compatibility matrix |
| Incomplete event coverage | Medium | High | Incremental implementation, focus on common patterns |
| Performance with large pipelines | Medium | Low | Implement lazy evaluation, add caching |
| Upstream refactoring | High | Low | Abstract interception points, maintain upgrade guide |

---

## 8. Future Enhancements

### 8.1 Version 2.0 Features
- Web UI for pipeline visualization
- Integration with VS Code and IntelliJ
- Real runner execution mode (not just mock); partly done: `run` executes a job on the host, without containers
- Pipeline metrics and optimization suggestions

### 8.2 Ecosystem Integration
- GitHub Actions compatibility layer
- Export to other CI formats
- Integration with container registries
- Cost estimation based on runner types

---

## 9. User Experience

### 9.1 Installation and Setup
1. Clone the repository and enter Nix shell:
   ```bash
   git clone https://github.com/eisbaw/gitlab_local_ci.git
   cd gitlab_local_ci
   nix develop  # Loads all dependencies from flake.nix
   ```

   Or run the packaged CLI without a clone of the dev environment:
   `nix run github:eisbaw/gitlab_local_ci -- lint`.

2. Initialize the GitLab submodule and the development gems:
   ```bash
   just setup
   ```

3. Set up runner fleet (optional):
   ```bash
   mkdir runners/
   # Create runner JSON files (see docs/runners.md)
   ```

4. Verify installation:
   ```bash
   just help  # Show available commands
   gitlab_ci_cli --help
   ```

### 9.2 Basic Workflow

**Step 1: Validate Configuration**
```bash
cd my-project/
gitlab_ci_cli --lint
# Outputs errors/warnings and exits with appropriate status
```

**Step 2: Visualize Pipeline**
```bash
gitlab_ci_cli --dag | dot -Tpng -o pipeline.png
# Opens pipeline.png to see job dependencies
```

**Step 3: Simulate Execution**
```bash
gitlab_ci_cli --dry-run --env DEPLOY_ENV=staging
# Shows job scheduling order and runner assignments
```

**Step 4: Debug Variables**
```bash
gitlab_ci_cli --dry-run --undefined=error
# Fails fast on undefined variables
```

### 9.3 Advanced Usage

**Child Pipeline Testing:**
```bash
# Automatically descends into triggered projects
gitlab_ci_cli --dry-run
# Output shows nested pipeline execution
```

**Custom Runner Fleet:**
```bash
gitlab_ci_cli --dry-run --runners ./custom-runners/
# Uses alternative runner configuration directory
```

---

## 10. Example Usage Scenarios

### 9.1 Basic Validation
```bash
$ gitlab_ci_cli lint
✓ Configuration is valid
  Stages: build → test → deploy
  Jobs: 8
```

### 9.2 DAG Visualization
```bash
$ gitlab_ci_cli dag | dot -Tpng -o pipeline.png
Generated pipeline.png with 12 jobs and 18 dependencies
```

### 9.3 Dry Run with Custom Variables
```bash
$ gitlab_ci_cli dry-run \
    --variables ENVIRONMENT=staging \
    --variables DEPLOY_TOKEN=$TOKEN \
    --undefined=error

Pipeline #1 created with 12 jobs

[T+0s] Job 'build-frontend' → Runner 'docker-runner-01'
[T+0s] Job 'build-backend' → Runner 'docker-runner-02'
[T+1s] Job 'test-unit' → Runner 'docker-runner-01'
[T+2s] Job 'test-integration' waiting (no eligible runner)
...
Pipeline completed: success
```

### 9.4 Child Pipeline Trigger
```bash
$ gitlab_ci_cli dry-run
Pipeline #1 created with 3 jobs

[T+0s] Job 'trigger-downstream' → Runner 'shell-runner-01'
  Triggering child pipeline in project 'microservice-a'
  Child pipeline #2 created with 5 jobs
  ...
  Child pipeline completed: success
  
Pipeline completed: success
```

---

## 10. Appendix

### A. GitLab Source File Mapping

| Functionality | GitLab Source Path | Mock Module |
|--------------|-------------------|-------------|
| YAML Parsing | `lib/gitlab/ci/yaml_processor.rb` | MockServer |
| Config Validation | `lib/gitlab/ci/config.rb` | MockServer |
| Pipeline Creation | `app/services/ci/create_pipeline_service.rb` | MockServer |
| Job Scheduling | `app/services/ci/register_job_service.rb` | RunnerFleet |
| State Machine | `app/models/ci/pipeline.rb` | MockServer |

### B. Event Schema

```json
{
  "event_type": "job_assigned",
  "timestamp": "2025-10-13T10:00:00Z",
  "payload": {
    "job_id": 12345,
    "job_name": "test-job",
    "runner_id": "runner_001",
    "stage": "test",
    "image": "ruby:3.0",
    "script": ["bundle install", "rspec"],
    "variables": {},
    "artifacts": {}
  }
}
```

### C. Configuration File Example

```yaml
# .gitlab-ci-cli.yml
runners_dir: ./runners
gitlab_dir: ./gitlab
undefined_mode: warning
default_variables:
  CI_DEBUG: "true"
  ENVIRONMENT: "development"
```
