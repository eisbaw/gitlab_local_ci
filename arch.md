# Architecture

## Overview

`gitlab_ci_cli` is built on a three-module design that simulates GitLab CI/CD pipelines locally without requiring a GitLab server. The architecture follows an event-driven approach to capture runner communication rather than reimplementing GitLab's internal logic.

## Three-Module Design

The system is composed of three primary modules that work together to simulate pipeline execution:

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

### Module 1: Mock GitLab Server

The Mock GitLab Server module handles all server-side responsibilities:

- **YAML Parsing**: Uses upstream `Gitlab::Ci::YamlProcessor` to parse `.gitlab-ci.yml` files
- **DAG Construction**: Leverages `Gitlab::Ci::YamlProcessor::Dag` to build the directed acyclic graph of job dependencies
- **Pipeline Logic**: Employs `Ci::CreatePipelineService` for pipeline creation and `Ci::ProcessPipelineService` for state management
- **Job Scheduling**: Intercepts `Ci::RegisterJobService` to capture job assignment events

The module reuses GitLab's own classes to ensure 100% compatibility with GitLab CI YAML syntax and behavior.

### Module 2: Runner Fleet Manager

The Runner Fleet Manager loads and manages mock runner configurations:

- Loads runner definitions from JSON files in the `runners/` directory
- Matches jobs to available runners based on tags, executor types, and capacity
- Tracks runner capacity and concurrent job limits
- Provides runner selection logic for job assignment

Runners are defined in a simple JSON format (see `docs/runner_format.md`) that can be hand-crafted or exported from production GitLab instances.

### Module 3: Mock Runner Client

The Mock Runner Client simulates individual runner behavior:

- Receives job assignment events from the scheduler
- Logs detailed job information (script, image, services, artifacts)
- Emits state transition events (job started, job completed)
- Does not execute actual job scripts (dry-run mode)

In future versions, this module could be replaced with real execution logic while keeping Modules 1 and 2 unchanged.

## Event-Driven Architecture

Instead of implementing HTTP API endpoints and network communication, `gitlab_ci_cli` uses an event-driven approach to capture the communication between GitLab server components and runners.

### Key Concepts

1. **Event Interception**: Rather than making HTTP requests, the system intercepts method calls at strategic points in GitLab's codebase
2. **Event Emission**: When jobs are assigned or state changes occur, events are emitted to a central event bus
3. **Event Handlers**: Mock runners subscribe to events and respond accordingly
4. **Decoupled Design**: This approach decouples scheduling from execution, enabling future extensibility

### Event Flow Example

```
1. User runs: gitlab_ci_cli dry-run
2. MockServer parses .gitlab-ci.yml
3. MockServer creates pipeline and jobs
4. JobScheduler intercepts Ci::RegisterJobService
5. Event emitted: {type: "job_assigned", job: {...}, runner: "runner_001"}
6. MockRunner receives event
7. MockRunner logs job details
8. MockRunner emits: {type: "job_started", job_id: 123}
9. MockRunner emits: {type: "job_completed", job_id: 123, status: "success"}
10. Pipeline completes
```

This event-driven approach provides several benefits:

- **Future Extensibility**: Mock components can be swapped with real executors
- **Testability**: Events can be captured and verified in tests
- **Visibility**: Full pipeline execution trace available for debugging
- **No Network Layer**: Eliminates complexity of HTTP communication

See `docs/event_schema.md` for detailed event specifications.

## GitLab Integration Strategy

### Zero-Patch Policy

The core principle of `gitlab_ci_cli` is to use GitLab source code without modification. This is achieved through:

1. **Git Submodule**: GitLab CE is imported as an unmodified submodule at `gitlab/`
2. **Wrapper Classes**: Custom logic wraps GitLab classes without modifying them
3. **Monkey Patching**: When necessary, Ruby's dynamic features allow method interception
4. **Version Pinning**: GitLab submodule locked to specific tags for stability

### Benefits of Zero-Patch Policy

- **Upstream Compatibility**: Easy to track and update to new GitLab versions
- **Reliability**: Using battle-tested GitLab code ensures correctness
- **Maintenance**: No need to maintain patches across GitLab releases
- **Trust**: Users can verify that actual GitLab logic is being used

### Integration Points

The following GitLab classes are reused directly:

| Class | Purpose | Module |
|-------|---------|--------|
| `Gitlab::Ci::YamlProcessor` | YAML parsing and validation | MockServer |
| `Gitlab::Ci::YamlProcessor::Dag` | DAG construction and cycle detection | MockServer |
| `Gitlab::Ci::Config` | Configuration validation | MockServer |
| `Ci::CreatePipelineService` | Pipeline creation | MockServer |
| `Ci::ProcessPipelineService` | State transitions | MockServer |
| `Ci::RegisterJobService` | Job scheduling (intercepted) | RunnerFleet |

### Interception Example

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

## Git Submodule Strategy

The project structure uses a git submodule to include the entire GitLab CE repository:

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

### Submodule Management

**Initial Setup:**
```bash
git submodule update --init
bundle install
```

**Updating GitLab Version:**
```bash
cd gitlab
git fetch
git checkout v17.0.0  # Or desired version tag
cd ..
git add gitlab
git commit -m "Update GitLab submodule to v17.0.0"
```

**Version Pinning:**

The `.gitmodules` file locks the submodule to a specific commit, ensuring reproducible builds:

```
[submodule "gitlab"]
    path = gitlab
    url = https://gitlab.com/gitlab-org/gitlab.git
    branch = master
```

### Trade-offs

| Aspect | Benefit | Cost |
|--------|---------|------|
| **Submodule Size** | Complete GitLab source available | Adds ~100MB to repository |
| **Update Frequency** | Pin to stable releases | Must manually update submodule |
| **Compatibility** | Use actual GitLab code | May need updates when GitLab refactors |
| **Trust** | Verifiable, unmodified code | Cannot customize GitLab internals |

### Abstraction Strategy

To minimize breakage from upstream refactoring:

1. **Wrapper Classes**: Create thin wrappers around GitLab classes
2. **Compatibility Layer**: Isolate version-specific behavior in dedicated modules
3. **Integration Tests**: Verify functionality against multiple GitLab versions
4. **Documentation**: Maintain compatibility matrix for supported versions

## Architecture Trade-offs

| Decision | Pros | Cons |
|----------|------|------|
| **Ruby Implementation** | Direct reuse of GitLab classes, no translation layer | Must maintain Ruby environment |
| **Git Submodule** | Zero patches, easy upstream tracking | Adds ~100MB to repository, version pinning complexity |
| **Event-Driven Runner Interface** | Decouples scheduling from execution, future extensibility | Requires modeling concurrency and job acknowledgment |
| **JSON Fleet Format** | Human-readable, easy to export from production | May not capture all runner settings |
| **In-Memory Simulation** | Fast, no external dependencies | No persistence between runs |

## Critical Design Constraints

1. **No GitLab Patches**: All adaptations must use wrapper classes or Ruby metaprogramming
2. **Version Pinning**: Lock GitLab submodule to specific tags for stability
3. **Upstream Refactoring**: Abstract interception points to minimize breakage from GitLab changes
4. **Ruby-Native**: Written in Ruby to maximize code reuse from upstream GitLab

## Future Architecture Considerations

### Real Execution Mode

The event-driven architecture enables future replacement of mock components:

- Module 3 (Mock Runner) could be replaced with a real executor
- Docker, Kubernetes, or shell executors could subscribe to job assignment events
- Module 1 and 2 remain unchanged

### Distributed Simulation

For capacity planning scenarios:

- Multiple runner processes could subscribe to the same event bus
- Real concurrency and queueing behavior could be simulated
- Network latency and failure modes could be introduced

### Web UI Integration

The event stream could power a web-based visualization:

- Real-time pipeline execution display
- Interactive DAG exploration
- Job log streaming (when real execution is enabled)
