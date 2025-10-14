# Runner Format

## Overview

`gitlab_ci_cli` uses JSON files to define mock runners. These files are placed in the `runners/` directory and are loaded when the tool starts.

Each JSON file represents a single runner with its configuration, tags, and capacity limits.

## File Location

Runner definitions are stored as JSON files in the `runners/` directory:

```
gitlab_ci_cli/
├── runners/
│   ├── runner1.json
│   ├── runner2.json
│   ├── docker-runner.json
│   └── shell-runner.json
```

The CLI loads all `.json` files from this directory automatically. You can override the directory location with the `--runners` command-line option:

```bash
gitlab_ci_cli dry-run --runners ./custom-runners/
```

## Minimal Format (MVP)

For quick setup and testing, runners can be defined with just the essential fields:

```json
{
  "id": "runner-1",
  "tags": ["docker", "linux"],
  "executor": "shell",
  "max_jobs": 2
}
```

### Minimal Format Fields

- **id** (string, required): Unique identifier for this runner
  - Used in event logs and output
  - Must be unique across all runners in the fleet

- **tags** (array of strings, required): Tags this runner matches
  - Jobs with matching tags can be assigned to this runner
  - Empty array means runner only accepts untagged jobs

- **executor** (string, required): Executor type
  - Supported values: `"shell"`, `"docker"`, `"kubernetes"`, `"ssh"`, `"parallels"`, `"virtualbox"`
  - In dry-run mode, this is informational only

- **max_jobs** (integer, required): Maximum concurrent jobs
  - How many jobs this runner can execute simultaneously
  - Must be >= 1

### Minimal Format Example

```json
{
  "id": "my-docker-runner",
  "tags": ["docker", "linux"],
  "executor": "docker",
  "max_jobs": 4
}
```

## Extended Format (Future)

The extended format includes additional fields for more realistic simulation and future features like real execution:

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

### Extended Format Fields

#### Basic Information

- **id** (string, required): Unique runner identifier
- **description** (string, optional): Human-readable description
- **active** (boolean, optional, default: true): Whether runner is active

#### Tag Configuration

- **tags** (array of strings, required): Tags this runner matches
- **run_untagged** (boolean, optional, default: false): Accept jobs without tags
- **locked** (boolean, optional, default: false): Runner locked to specific project

#### Access Control

- **access_level** (string, optional, default: "not_protected"): Runner access level
  - Values: `"not_protected"`, `"ref_protected"`
  - Protected runners only run jobs on protected branches

#### Execution Limits

- **maximum_timeout** (integer, optional, default: 3600): Maximum job timeout in seconds
- **concurrent** (integer, optional): Alias for `max_jobs`

#### Executor Configuration

- **executor** (string, required): Executor type
- **executor_config** (object, optional): Executor-specific configuration

##### Docker Executor Config

```json
{
  "executor": "docker",
  "executor_config": {
    "image": "alpine:latest",
    "privileged": false,
    "volumes": ["/cache", "/builds:/builds"],
    "services": ["postgres:13"],
    "pull_policy": ["always"],
    "network_mode": "bridge",
    "shm_size": 67108864
  }
}
```

**Fields:**
- `image`: Default Docker image if job doesn't specify one
- `privileged`: Run containers in privileged mode
- `volumes`: Volume mounts for containers
- `services`: Default services to start
- `pull_policy`: When to pull images (always, if-not-present, never)
- `network_mode`: Docker network mode
- `shm_size`: Shared memory size in bytes

##### Kubernetes Executor Config

```json
{
  "executor": "kubernetes",
  "executor_config": {
    "namespace": "gitlab-runners",
    "image": "alpine:latest",
    "cpu_request": "1",
    "cpu_limit": "2",
    "memory_request": "1Gi",
    "memory_limit": "2Gi",
    "service_account": "gitlab-runner",
    "pull_policy": "if-not-present"
  }
}
```

##### Shell Executor Config

```json
{
  "executor": "shell",
  "executor_config": {
    "shell": "bash",
    "user": "gitlab-runner"
  }
}
```

#### Capacity Tracking

- **capacity** (object, optional): Current capacity information
  - `running_jobs` (integer): Number of currently running jobs
  - `max_jobs` (integer): Maximum concurrent jobs (same as `concurrent` or `max_jobs`)

In dry-run mode, `running_jobs` is tracked internally during simulation.

### Extended Format Example

```json
{
  "id": "production-docker-runner-1",
  "description": "Production Docker runner on AWS EC2 c5.2xlarge",
  "active": true,
  "tags": ["docker", "linux", "amd64", "production"],
  "run_untagged": false,
  "locked": false,
  "access_level": "ref_protected",
  "maximum_timeout": 7200,
  "executor": "docker",
  "executor_config": {
    "image": "ruby:3.0",
    "privileged": false,
    "volumes": ["/cache", "/var/run/docker.sock:/var/run/docker.sock"],
    "pull_policy": ["if-not-present"]
  },
  "concurrent": 8,
  "capacity": {
    "running_jobs": 0,
    "max_jobs": 8
  }
}
```

## Tag Matching Logic

Jobs are matched to runners based on tags:

### Job with Tags

```yaml
# .gitlab-ci.yml
test:
  tags:
    - docker
    - linux
  script: echo "Testing"
```

This job can be assigned to any runner that has **both** the `docker` AND `linux` tags.

### Job without Tags

```yaml
# .gitlab-ci.yml
test:
  script: echo "Testing"
```

This job can only be assigned to runners with `run_untagged: true`.

### Matching Algorithm

```ruby
def runner_can_handle_job?(runner, job)
  # Check if runner has capacity
  return false unless runner.has_capacity?

  # Check if runner is active
  return false unless runner.active?

  # If job has no tags, runner must accept untagged jobs
  if job.tags.empty?
    return runner.run_untagged?
  end

  # Job tags must be a subset of runner tags
  job.tags.all? { |tag| runner.tags.include?(tag) }
end
```

## Exporting from Production GitLab

You can export runner configurations from a live GitLab instance using the GitLab API:

### Using API Token

```bash
# Get all runners
curl --header "PRIVATE-TOKEN: <your_token>" \
  "https://gitlab.example.com/api/v4/runners/all" > all_runners.json

# Extract specific runners
curl --header "PRIVATE-TOKEN: <your_token>" \
  "https://gitlab.example.com/api/v4/runners/123" > runners/runner_123.json
```

### Using Companion Script

A future companion script will automate this process:

```ruby
# tools/export_runners.rb
class RunnerExporter
  def export_from_gitlab(gitlab_url, token, output_dir = './runners')
    client = Gitlab.client(
      endpoint: gitlab_url,
      private_token: token
    )

    runners = client.runners(per_page: 100)

    runners.each do |runner|
      File.write(
        "#{output_dir}/runner_#{runner.id}.json",
        JSON.pretty_generate(runner.to_h)
      )
    end

    puts "Exported #{runners.count} runners to #{output_dir}"
  end
end
```

Usage:

```bash
ruby tools/export_runners.rb \
  --url https://gitlab.example.com \
  --token $GITLAB_TOKEN \
  --output ./runners
```

## Example Runner Fleet

### Small Development Fleet

```bash
# runners/docker-runner.json
{
  "id": "docker-1",
  "tags": ["docker", "linux"],
  "executor": "docker",
  "max_jobs": 2
}

# runners/shell-runner.json
{
  "id": "shell-1",
  "tags": ["shell", "macos"],
  "executor": "shell",
  "max_jobs": 1
}
```

### Production-Like Fleet

```bash
# runners/prod-docker-1.json
{
  "id": "prod-docker-1",
  "description": "Production Docker runner 1",
  "tags": ["docker", "linux", "production"],
  "executor": "docker",
  "max_jobs": 8,
  "run_untagged": false,
  "access_level": "ref_protected"
}

# runners/prod-docker-2.json
{
  "id": "prod-docker-2",
  "description": "Production Docker runner 2",
  "tags": ["docker", "linux", "production"],
  "executor": "docker",
  "max_jobs": 8,
  "run_untagged": false,
  "access_level": "ref_protected"
}

# runners/staging-docker.json
{
  "id": "staging-docker",
  "description": "Staging Docker runner",
  "tags": ["docker", "linux", "staging"],
  "executor": "docker",
  "max_jobs": 4,
  "run_untagged": true
}
```

## Validation

Runner JSON files are validated when loaded:

### Required Fields Check

```ruby
def validate_runner_config(config)
  required = ['id', 'tags', 'executor', 'max_jobs']
  missing = required - config.keys

  if missing.any?
    raise "Runner config missing required fields: #{missing.join(', ')}"
  end
end
```

### Type Validation

```ruby
def validate_types(config)
  unless config['id'].is_a?(String)
    raise "Runner 'id' must be a string"
  end

  unless config['tags'].is_a?(Array)
    raise "Runner 'tags' must be an array"
  end

  unless config['max_jobs'].is_a?(Integer) && config['max_jobs'] > 0
    raise "Runner 'max_jobs' must be a positive integer"
  end
end
```

## Command-Line Options

### Specifying Runner Directory

```bash
# Default: ./runners/
gitlab_ci_cli dry-run

# Custom directory
gitlab_ci_cli dry-run --runners /path/to/runners/

# Relative path
gitlab_ci_cli dry-run --runners ../shared-runners/
```

### Loading Specific Runners

While not currently implemented, future versions may support:

```bash
# Load specific runner files
gitlab_ci_cli dry-run --runner runners/docker-1.json --runner runners/shell-1.json

# Load all runners matching pattern
gitlab_ci_cli dry-run --runners "production-*.json"
```

## Runner Fleet Management

### Creating a Fleet

```bash
mkdir runners/

cat > runners/docker-1.json <<EOF
{
  "id": "docker-1",
  "tags": ["docker", "linux"],
  "executor": "docker",
  "max_jobs": 4
}
EOF

cat > runners/docker-2.json <<EOF
{
  "id": "docker-2",
  "tags": ["docker", "linux"],
  "executor": "docker",
  "max_jobs": 4
}
EOF
```

### Viewing Fleet Status

```bash
# Future feature: list runners
gitlab_ci_cli runners list

# Output:
# ID         Tags              Executor   Max Jobs   Status
# docker-1   docker, linux     docker     4          active
# docker-2   docker, linux     docker     4          active
```

## Best Practices

### Naming Conventions

- Use descriptive IDs: `prod-docker-1`, `staging-shell`, etc.
- Include environment in tags: `production`, `staging`, `development`
- Be specific with executor types in IDs: `docker-runner-1`, `k8s-runner-1`

### Capacity Planning

- Match production runner capacity for realistic simulation
- Set `max_jobs` based on runner hardware capabilities
- Consider job types when setting capacity (CPU-bound vs I/O-bound)

### Tag Strategy

- Use consistent tag naming across your organization
- Include platform: `linux`, `macos`, `windows`
- Include architecture: `amd64`, `arm64`
- Include special capabilities: `gpu`, `large-disk`, `privileged`

### Fleet Organization

For large fleets, organize runners by subdirectory:

```
runners/
├── production/
│   ├── docker-1.json
│   ├── docker-2.json
│   └── k8s-1.json
├── staging/
│   └── docker-1.json
└── development/
    ├── shell-1.json
    └── docker-1.json
```

Load specific environments:

```bash
gitlab_ci_cli dry-run --runners runners/production/
```

## Future Enhancements

Planned improvements to runner format:

- **Auto-scaling**: Simulate runner auto-scaling behavior
- **Cost Tracking**: Estimate CI costs based on runner types and usage
- **Failure Simulation**: Introduce random runner failures for testing
- **Network Latency**: Simulate network delays between server and runners
- **Resource Tracking**: Track CPU, memory, disk usage per runner
