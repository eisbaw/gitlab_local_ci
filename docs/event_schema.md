# Event Schema

## Overview

`gitlab_ci_cli` uses an event-driven architecture to simulate the communication between GitLab server components and runners. Instead of HTTP API calls, the system emits and handles events internally.

This document describes all event types used in the system and their payload structures.

## Event-Driven Architecture

### Why Events?

Traditional GitLab deployments use HTTP APIs for communication between the server and runners:

1. Runner polls server: `GET /api/v4/jobs/request`
2. Server responds with job payload
3. Runner executes job
4. Runner updates server: `PUT /api/v4/jobs/:id`

In `gitlab_ci_cli`, we replace HTTP communication with in-process events:

1. Mock server intercepts job scheduling logic
2. Event emitted: `{type: "job_assigned", ...}`
3. Mock runner receives event
4. Mock runner logs job details
5. Mock runner emits: `{type: "job_completed", ...}`

### Benefits

- **No Network Layer**: Eliminates HTTP overhead and complexity
- **Synchronous Execution**: Events processed immediately for fast simulation
- **Full Visibility**: Complete event trace available for debugging
- **Extensibility**: Easy to add new event handlers or replace components

## Event Structure

All events follow a common structure:

```json
{
  "event_type": "string",
  "timestamp": "ISO 8601 timestamp",
  "payload": {
    // Event-specific data
  }
}
```

### Common Fields

- **event_type** (string, required): The type of event (see Event Types below)
- **timestamp** (string, required): ISO 8601 formatted timestamp when event was emitted
- **payload** (object, required): Event-specific data (varies by event type)

## Event Types

### 1. Pipeline Events

#### pipeline_created

Emitted when a new pipeline is created from a `.gitlab-ci.yml` file.

**Payload:**

```json
{
  "event_type": "pipeline_created",
  "timestamp": "2025-10-13T10:00:00Z",
  "payload": {
    "pipeline_id": 1,
    "ref": "main",
    "sha": "abc123def456",
    "source": "push",
    "stages": ["build", "test", "deploy"],
    "job_count": 12,
    "variables": {
      "CI_COMMIT_REF_NAME": "main",
      "CUSTOM_VAR": "value"
    }
  }
}
```

**Fields:**

- `pipeline_id`: Unique identifier for this pipeline
- `ref`: Git reference (branch, tag, or commit)
- `sha`: Git commit SHA
- `source`: Pipeline source (push, merge_request, schedule, manual, etc.)
- `stages`: Ordered list of stage names
- `job_count`: Total number of jobs in the pipeline
- `variables`: CI/CD variables available to the pipeline

#### pipeline_completed

Emitted when all jobs in a pipeline have finished.

**Payload:**

```json
{
  "event_type": "pipeline_completed",
  "timestamp": "2025-10-13T10:15:00Z",
  "payload": {
    "pipeline_id": 1,
    "status": "success",
    "duration_seconds": 900,
    "job_summary": {
      "success": 10,
      "failed": 0,
      "skipped": 2
    }
  }
}
```

**Fields:**

- `pipeline_id`: Pipeline identifier
- `status`: Final status (success, failed, canceled, skipped)
- `duration_seconds`: Total pipeline execution time
- `job_summary`: Count of jobs by status

### 2. Job Events

#### job_assigned

Emitted when the scheduler assigns a job to a runner.

**Payload:**

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
    "before_script": ["echo 'Starting job'"],
    "after_script": ["echo 'Job finished'"],
    "services": ["postgres:13", "redis:6"],
    "variables": {
      "DATABASE_URL": "postgres://localhost/test",
      "RAILS_ENV": "test"
    },
    "artifacts": {
      "paths": ["coverage/", "test-results.xml"],
      "when": "always",
      "expire_in": "30 days"
    },
    "cache": {
      "key": "bundle-gems",
      "paths": ["vendor/bundle"]
    },
    "needs": ["build-job"],
    "tags": ["docker", "linux"]
  }
}
```

**Fields:**

- `job_id`: Unique job identifier
- `job_name`: Job name from `.gitlab-ci.yml`
- `runner_id`: ID of runner assigned to execute this job
- `stage`: Stage name this job belongs to
- `image`: Docker image to use (for Docker executor)
- `script`: Array of script commands to execute
- `before_script`: Commands to run before main script
- `after_script`: Commands to run after main script (always executes)
- `services`: Array of service containers to start
- `variables`: Job-specific variables (merged with pipeline variables)
- `artifacts`: Artifact collection configuration
- `cache`: Cache configuration
- `needs`: Array of job names this job depends on
- `tags`: Runner tags required for this job

#### job_started

Emitted when a runner begins executing a job.

**Payload:**

```json
{
  "event_type": "job_started",
  "timestamp": "2025-10-13T10:00:05Z",
  "payload": {
    "job_id": 12345,
    "runner_id": "runner_001"
  }
}
```

**Fields:**

- `job_id`: Job identifier
- `runner_id`: Runner executing the job

#### job_completed

Emitted when a job finishes execution (success or failure).

**Payload:**

```json
{
  "event_type": "job_completed",
  "timestamp": "2025-10-13T10:02:30Z",
  "payload": {
    "job_id": 12345,
    "runner_id": "runner_001",
    "status": "success",
    "duration_seconds": 145,
    "exit_code": 0,
    "artifacts_collected": true
  }
}
```

**Fields:**

- `job_id`: Job identifier
- `runner_id`: Runner that executed the job
- `status`: Final status (success, failed, canceled)
- `duration_seconds`: Job execution time
- `exit_code`: Script exit code (0 for success)
- `artifacts_collected`: Whether artifacts were successfully collected

#### job_waiting

Emitted when a job cannot be scheduled due to missing runner capacity or matching tags.

**Payload:**

```json
{
  "event_type": "job_waiting",
  "timestamp": "2025-10-13T10:00:00Z",
  "payload": {
    "job_id": 12346,
    "job_name": "deploy-production",
    "stage": "deploy",
    "reason": "no_matching_runner",
    "required_tags": ["deploy", "production"],
    "available_runners": 0
  }
}
```

**Fields:**

- `job_id`: Job identifier
- `job_name`: Job name
- `stage`: Stage name
- `reason`: Why job is waiting (no_matching_runner, capacity_full, dependencies_pending)
- `required_tags`: Tags required by the job
- `available_runners`: Count of runners that could match (if they had capacity)

### 3. Runner Events

#### runner_registered

Emitted when a mock runner is loaded from the runner fleet.

**Payload:**

```json
{
  "event_type": "runner_registered",
  "timestamp": "2025-10-13T09:59:00Z",
  "payload": {
    "runner_id": "runner_001",
    "tags": ["docker", "linux", "amd64"],
    "executor": "docker",
    "max_jobs": 4,
    "run_untagged": true
  }
}
```

**Fields:**

- `runner_id`: Unique runner identifier
- `tags`: Tags this runner matches
- `executor`: Executor type (shell, docker, kubernetes, etc.)
- `max_jobs`: Maximum concurrent jobs
- `run_untagged`: Whether runner accepts jobs without tags

### 4. Child Pipeline Events

#### child_pipeline_created

Emitted when a job triggers a child/downstream pipeline.

**Payload:**

```json
{
  "event_type": "child_pipeline_created",
  "timestamp": "2025-10-13T10:05:00Z",
  "payload": {
    "parent_job_id": 12350,
    "child_pipeline_id": 2,
    "child_project": "microservice-a",
    "config_file": ".gitlab-ci.yml",
    "strategy": "depend"
  }
}
```

**Fields:**

- `parent_job_id`: ID of job that triggered the child pipeline
- `child_pipeline_id`: ID of the created child pipeline
- `child_project`: Project path where child pipeline runs
- `config_file`: CI config file used for child pipeline
- `strategy`: Trigger strategy (depend means parent waits for child)

#### child_pipeline_completed

Emitted when a child pipeline finishes.

**Payload:**

```json
{
  "event_type": "child_pipeline_completed",
  "timestamp": "2025-10-13T10:10:00Z",
  "payload": {
    "parent_job_id": 12350,
    "child_pipeline_id": 2,
    "status": "success"
  }
}
```

**Fields:**

- `parent_job_id`: ID of parent job
- `child_pipeline_id`: ID of child pipeline
- `status`: Final child pipeline status

## Event Flow Diagram

```
User Command
    │
    ▼
┌─────────────────────────┐
│  Parse .gitlab-ci.yml   │
└───────────┬─────────────┘
            │
            ▼
    pipeline_created
            │
            ▼
┌─────────────────────────┐
│   Job Scheduler Loop    │
└───────────┬─────────────┘
            │
    ┌───────┴────────┐
    │                │
    ▼                ▼
job_assigned    job_waiting
    │
    ▼
job_started
    │
    ▼
job_completed
    │
    ▼
pipeline_completed
```

## Event Handling Example

### Mock Runner Event Handler

```ruby
class MockRunner
  def handle_job_assignment(event)
    job = event[:payload]

    puts "Runner #{@id} received job ##{job[:job_id]}"
    puts "  Project: #{job[:project_name]}"
    puts "  Stage: #{job[:stage]}"
    puts "  Job: #{job[:job_name]}"
    puts "  Script:"
    job[:script].each { |cmd| puts "    $ #{cmd}" }
    puts "  Image: #{job[:image]}"
    puts "  Services: #{job[:services].join(', ')}" if job[:services]
    puts "  Artifacts: #{job[:artifacts]}" if job[:artifacts]

    # Simulate state transitions
    emit_event(:job_started, {
      job_id: job[:job_id],
      runner_id: @id
    })

    # In dry-run mode, immediately complete
    emit_event(:job_completed, {
      job_id: job[:job_id],
      runner_id: @id,
      status: 'success',
      duration_seconds: 0,
      exit_code: 0,
      artifacts_collected: job[:artifacts].present?
    })
  end
end
```

### Event Bus Implementation

```ruby
class EventBus
  def initialize
    @handlers = Hash.new { |h, k| h[k] = [] }
  end

  def subscribe(event_type, handler)
    @handlers[event_type] << handler
  end

  def emit(event_type, payload)
    event = {
      event_type: event_type,
      timestamp: Time.now.iso8601,
      payload: payload
    }

    @handlers[event_type].each do |handler|
      handler.call(event)
    end

    # Log all events for debugging
    log_event(event) if ENV['CI_DEBUG']
  end
end
```

## Event Storage and Replay

For debugging and testing, events can be logged to a file:

```json
[
  {
    "event_type": "pipeline_created",
    "timestamp": "2025-10-13T10:00:00Z",
    "payload": {...}
  },
  {
    "event_type": "job_assigned",
    "timestamp": "2025-10-13T10:00:01Z",
    "payload": {...}
  },
  {
    "event_type": "job_started",
    "timestamp": "2025-10-13T10:00:02Z",
    "payload": {...}
  }
]
```

This event log can be:

- Analyzed for debugging pipeline behavior
- Replayed to reproduce issues
- Used in integration tests to verify correct event sequences
- Exported for visualization tools

## Future Event Types

The following events may be added in future versions:

- `artifact_uploaded`: When real execution mode uploads artifacts
- `cache_hit` / `cache_miss`: Cache behavior tracking
- `runner_failed`: Runner failure or timeout
- `job_retried`: Automatic job retry on failure
- `manual_action_triggered`: User triggers manual job
- `environment_deployed`: Deployment to environment completed
