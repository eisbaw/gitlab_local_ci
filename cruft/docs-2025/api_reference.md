# API Reference

This document provides detailed API documentation for the main classes and modules in gitlab_ci_cli.

## Table of Contents

- [Commands](#commands)
  - [LintCommand](#lintcommand)
  - [DagCommand](#dagcommand)
  - [DryRunCommand](#dryruncommand)
- [Core Classes](#core-classes)
  - [MockServer](#mockserver)
  - [MockJob](#mockjob)
  - [MockRunner](#mockrunner)
  - [RunnerFleet](#runnerfleet)
- [Utilities](#utilities)
  - [VariableExpander](#variableexpander)
  - [IncludeProcessor](#includeprocessor)
  - [ChildPipelineHandler](#childpipelinehandler)
  - [RunnerExporter](#runnerexporter)
- [Formatters](#formatters)

---

## Commands

### LintCommand

Validates GitLab CI YAML configuration files.

#### Methods

##### `execute(options)`

Validates a `.gitlab-ci.yml` file and returns validation results.

**Parameters:**
- `options` (Hash) - Configuration options
  - `:entry` (String) - Path to CI config file (default: `.gitlab-ci.yml`)
  - `:format` (String) - Output format: `text`, `json`, or `junit` (default: `text`)
  - `:verbose` (Boolean) - Enable verbose output (default: `false`)

**Returns:**
- `Result` object with:
  - `success` (Boolean) - Whether validation passed
  - `errors` (Array<String>) - List of validation errors
  - `stages` (Array<String>) - List of pipeline stages
  - `jobs` (Hash) - Parsed job configurations

**Example:**
```ruby
result = Commands::LintCommand.execute(
  entry: '.gitlab-ci.yml',
  format: 'json'
)

if result.success?
  puts "Valid: #{result.jobs.count} jobs in #{result.stages.count} stages"
else
  puts "Errors: #{result.errors.join(', ')}"
end
```

---

### DagCommand

Generates Graphviz DOT representation of pipeline dependencies.

#### Methods

##### `execute(options)`

Generates DAG visualization for a pipeline.

**Parameters:**
- `options` (Hash) - Configuration options
  - `:entry` (String) - Path to CI config file (default: `.gitlab-ci.yml`)
  - `:verbose` (Boolean) - Include diagnostic output (default: `false`)

**Returns:**
- `Result` object with:
  - `success` (Boolean) - Whether DAG generation succeeded
  - `dot_output` (String) - Graphviz DOT format output
  - `errors` (Array<String>) - List of errors (if any)

**Example:**
```ruby
result = Commands::DagCommand.execute(entry: '.gitlab-ci.yml')

if result.success?
  File.write('pipeline.dot', result.dot_output)
  system('dot -Tpng pipeline.dot -o pipeline.png')
end
```

---

### DryRunCommand

Simulates pipeline execution against a mock runner fleet.

#### Methods

##### `execute(options)`

Runs a dry-run simulation of pipeline execution.

**Parameters:**
- `options` (Hash) - Configuration options
  - `:entry` (String) - Path to CI config file
  - `:runners` (String) - Path to runners directory (default: `./runners`)
  - `:project` (String) - Project directory path
  - `:ref` (String) - Git reference (default: `HEAD`)
  - `:variables` (Hash) - CI variables
  - `:pipeline` (String) - Pipeline type: `push`, `merge_request`, `schedule`, `manual`
  - `:undefined` (Symbol) - Variable handling: `:warning`, `:error`, `:empty`
  - `:verbose` (Boolean) - Enable verbose output
  - `:format` (String) - Output format

**Returns:**
- `Result` object with:
  - `success` (Boolean) - Whether simulation completed
  - `timeline` (Array<Hash>) - Execution timeline events
  - `final_status` (String) - Pipeline final status
  - `jobs_executed` (Integer) - Number of jobs executed

**Example:**
```ruby
result = Commands::DryRunCommand.execute(
  entry: '.gitlab-ci.yml',
  runners: './runners',
  variables: { 'ENVIRONMENT' => 'staging' },
  undefined: :error
)

puts "Pipeline #{result.success? ? 'succeeded' : 'failed'}"
puts "Executed #{result.jobs_executed} jobs"
```

---

## Core Classes

### MockServer

Manages pipeline creation and execution simulation.

#### Methods

##### `initialize(gitlab_path: nil)`

Creates a new mock server instance.

**Parameters:**
- `gitlab_path` (String, optional) - Path to GitLab installation (unused, for compatibility)

##### `create_pipeline(config, options = {})`

Creates a pipeline from YAML configuration.

**Parameters:**
- `config` (String or Hash) - YAML content or parsed configuration
- `options` (Hash) - Pipeline options
  - `:ref` (String) - Git reference
  - `:variables` (Hash) - CI variables
  - `:pipeline_type` (String) - Type of pipeline

**Returns:**
- Pipeline object with stages and jobs

**Example:**
```ruby
server = MockServer.new
pipeline = server.create_pipeline(
  File.read('.gitlab-ci.yml'),
  ref: 'main',
  variables: { 'ENV' => 'prod' }
)

puts "Created pipeline with #{pipeline.jobs.count} jobs"
```

##### `has_pending_jobs?(pipeline)`

Checks if pipeline has pending jobs.

**Parameters:**
- `pipeline` - Pipeline object

**Returns:**
- Boolean indicating if pending jobs exist

##### `pending_jobs(pipeline)`

Returns list of pending jobs that can be scheduled.

**Parameters:**
- `pipeline` - Pipeline object

**Returns:**
- Array of MockJob objects

##### `process_pipeline(pipeline)`

Processes pipeline state transitions.

**Parameters:**
- `pipeline` - Pipeline object

**Returns:**
- Boolean indicating if state changed

##### `emit_event(event_type, payload)`

Emits an event to the event queue.

**Parameters:**
- `event_type` (Symbol) - Type of event
- `payload` (Hash) - Event data

**Example:**
```ruby
server.emit_event(:job_completed, {
  job_id: 123,
  status: 'success'
})
```

---

### MockJob

Represents a CI job with state machine behavior.

#### Attributes

- `id` (Integer) - Unique job identifier
- `name` (String) - Job name
- `stage` (String) - Stage name
- `script` (Array<String>) - Job script commands
- `image` (String, nil) - Docker image
- `services` (Array<String>) - Service containers
- `artifacts` (Hash, nil) - Artifact configuration
- `variables` (Hash) - Job variables
- `tag_list` (Array<String>) - Required runner tags
- `needs` (Array) - Job dependencies
- `status` (Symbol) - Current status

#### Status Constants

- `STATUS_PENDING` = `:pending`
- `STATUS_RUNNING` = `:running`
- `STATUS_COMPLETED` = `:completed`
- `STATUS_FAILED` = `:failed`
- `STATUS_CANCELED` = `:canceled`
- `STATUS_SKIPPED` = `:skipped`

#### Methods

##### `initialize(attributes)`

Creates a new job instance.

**Parameters:**
- `attributes` (Hash) - Job attributes

**Example:**
```ruby
job = MockJob.new(
  id: 1,
  name: 'test',
  stage: 'test',
  script: ['bundle exec rspec'],
  tag_list: ['docker']
)
```

##### `transition_to(new_status)`

Transitions job to a new status.

**Parameters:**
- `new_status` (Symbol) - Target status

**Raises:**
- `RuntimeError` if transition is invalid

**Example:**
```ruby
job.transition_to(:running)
job.transition_to(:completed)
```

##### `pending?`, `running?`, `completed?`, `failed?`, `canceled?`, `skipped?`

Status predicate methods.

**Returns:**
- Boolean indicating current status

##### `finished?`

Checks if job is in a terminal state.

**Returns:**
- Boolean (true if completed, failed, canceled, or skipped)

---

### MockRunner

Represents a mock CI runner.

#### Attributes

- `id` (String) - Runner identifier
- `tags` (Array<String>) - Runner tags
- `executor` (String) - Executor type
- `max_jobs` (Integer) - Maximum concurrent jobs
- `running_jobs` (Integer) - Currently running jobs count
- `run_untagged` (Boolean) - Accept untagged jobs

#### Methods

##### `initialize(data)`

Creates a new runner instance.

**Parameters:**
- `data` (Hash) - Runner configuration

**Example:**
```ruby
runner = MockRunner.new(
  'id' => 'runner_1',
  'tags' => ['docker', 'linux'],
  'max_jobs' => 2
)
```

##### `can_handle?(job)`

Checks if runner can handle a job based on tags.

**Parameters:**
- `job` (MockJob) - Job to check

**Returns:**
- Boolean indicating compatibility

**Example:**
```ruby
job = MockJob.new(tag_list: ['docker'])
runner = MockRunner.new('tags' => ['docker', 'linux'])

if runner.can_handle?(job)
  puts "Runner can handle this job"
end
```

##### `has_capacity?`

Checks if runner has capacity for more jobs.

**Returns:**
- Boolean (true if running_jobs < max_jobs)

##### `assign_job(job)`

Assigns a job to this runner.

**Parameters:**
- `job` (MockJob) - Job to assign

**Returns:**
- Boolean indicating success

**Example:**
```ruby
if runner.has_capacity? && runner.can_handle?(job)
  runner.assign_job(job)
end
```

##### `release_job(job)`

Releases a job from this runner.

**Parameters:**
- `job` (MockJob) - Job to release

**Returns:**
- Boolean indicating success

---

### RunnerFleet

Manages a collection of mock runners.

#### Methods

##### `initialize`

Creates a new runner fleet instance.

##### `load_runners(directory)`

Loads runner configurations from JSON files.

**Parameters:**
- `directory` (String) - Path to directory containing JSON files

**Returns:**
- Integer count of loaded runners

**Example:**
```ruby
fleet = RunnerFleet.new
count = fleet.load_runners('./runners')
puts "Loaded #{count} runners"
```

##### `find_available_runner(job)`

Finds an available runner for a job.

**Parameters:**
- `job` (MockJob) - Job requiring a runner

**Returns:**
- MockRunner instance or nil if none available

**Example:**
```ruby
runner = fleet.find_available_runner(job)
if runner
  runner.assign_job(job)
else
  puts "No available runner for job"
end
```

##### `runners`

Returns array of all loaded runners.

**Returns:**
- Array<MockRunner>

---

## Utilities

### VariableExpander

Expands CI variables in strings with configurable undefined variable handling.

#### Modes

- `:warning` - Warn about undefined variables, keep original
- `:error` - Raise error on undefined variables
- `:empty` - Replace undefined variables with empty string

#### Methods

##### `initialize(mode: :warning)`

Creates a new variable expander.

**Parameters:**
- `mode` (Symbol) - Handling mode for undefined variables

##### `expand(text, variables)`

Expands variables in text.

**Parameters:**
- `text` (String) - Text containing variable references
- `variables` (Hash) - Variable definitions

**Returns:**
- String with variables expanded

**Raises:**
- `UndefinedVariableError` if mode is `:error` and variable is undefined

**Example:**
```ruby
expander = VariableExpander.new(mode: :error)
result = expander.expand(
  'Deploy to ${ENV}',
  { 'ENV' => 'staging' }
)
# => "Deploy to staging"
```

---

### IncludeProcessor

Processes GitLab CI include directives.

#### Constants

- `INCLUDE_TYPES` - Array of supported include types
- `MAX_DEPTH` - Maximum include depth (150)

#### Methods

##### `initialize(project_path:)`

Creates a new include processor.

**Parameters:**
- `project_path` (String) - Base project path for resolving includes

##### `process_includes(config, depth = 0)`

Processes include directives in configuration.

**Parameters:**
- `config` (Hash) - Configuration hash
- `depth` (Integer) - Current recursion depth

**Returns:**
- Hash with includes processed and merged

**Raises:**
- `IncludeDepthExceededError` if depth exceeds MAX_DEPTH
- `StandardError` if circular include detected

**Example:**
```ruby
processor = IncludeProcessor.new(project_path: '/path/to/project')
config = processor.process_includes({
  'include' => 'shared/ci.yml',
  'stages' => ['build', 'test']
})
```

---

### ChildPipelineHandler

Handles trigger jobs that create child pipelines.

#### Constants

- `DEFAULT_MAX_DEPTH` - Default maximum recursion depth (10)

#### Methods

##### `initialize(max_depth: DEFAULT_MAX_DEPTH)`

Creates a new child pipeline handler.

**Parameters:**
- `max_depth` (Integer) - Maximum pipeline nesting depth

##### `trigger_child(parent_job, downstream_config, current_depth: 0)`

Triggers a child pipeline.

**Parameters:**
- `parent_job` (MockJob) - Parent job triggering the child
- `downstream_config` (Hash) - Child pipeline configuration
  - `:project` (String) - Child project path (required)
  - `:file` (String) - CI config file (default: `.gitlab-ci.yml`)
  - `:variables` (Hash) - Variables to pass to child
- `current_depth` (Integer) - Current nesting depth

**Returns:**
- Hash with:
  - `:success` (Boolean) - Whether child succeeded
  - `:exit_code` (Integer) - Child process exit code
  - `:output` (String) - Child process output

**Raises:**
- `RuntimeError` if depth limit exceeded or project not specified

**Example:**
```ruby
handler = ChildPipelineHandler.new
result = handler.trigger_child(
  parent_job,
  {
    project: '../downstream',
    file: '.gitlab-ci.yml',
    variables: { 'ENV' => 'staging' }
  }
)

puts "Child pipeline #{result[:success] ? 'succeeded' : 'failed'}"
```

---

### RunnerExporter

Exports runner configurations from GitLab API to JSON files.

#### Error Classes

- `APIError` - General API errors
- `NetworkError` - Network connection errors
- `AuthenticationError` - Authentication failures

#### Methods

##### `initialize`

Creates a new runner exporter instance.

##### `export_from_gitlab(gitlab_url, token, output_dir = './runners')`

Exports runners from a GitLab instance.

**Parameters:**
- `gitlab_url` (String) - GitLab instance URL
- `token` (String) - GitLab API token with `read_api` scope
- `output_dir` (String) - Directory to write JSON files

**Returns:**
- Integer count of exported runners

**Raises:**
- `ArgumentError` if URL or token is empty
- `AuthenticationError` if authentication fails
- `NetworkError` if network connection fails
- `APIError` for other API errors

**Example:**
```ruby
exporter = RunnerExporter.new
count = exporter.export_from_gitlab(
  'https://gitlab.example.com',
  ENV['GITLAB_TOKEN'],
  './runners'
)

puts "Exported #{count} runners"
```

---

## Formatters

### BaseFormatter

Abstract base class for output formatters.

#### Methods

##### `format(result)`

Formats a result object.

**Parameters:**
- `result` - Result object to format

**Returns:**
- String formatted output

### TextFormatter

Human-readable text output formatter.

**Example:**
```ruby
formatter = Formatters::TextFormatter.new
output = formatter.format(result)
puts output
```

### JsonFormatter

JSON output formatter for machine consumption.

**Example:**
```ruby
formatter = Formatters::JsonFormatter.new
output = formatter.format(result)
File.write('result.json', output)
```

### JunitFormatter

JUnit XML output formatter for CI integration.

**Example:**
```ruby
formatter = Formatters::JunitFormatter.new
output = formatter.format(result)
File.write('results.xml', output)
```

---

## Usage Examples

### Complete Pipeline Simulation

```ruby
# Load configuration
config = File.read('.gitlab-ci.yml')

# Create server and fleet
server = MockServer.new
fleet = RunnerFleet.new
fleet.load_runners('./runners')

# Create pipeline
pipeline = server.create_pipeline(config, ref: 'main')

# Simulate execution
time = 0
while server.has_pending_jobs?(pipeline)
  server.process_pipeline(pipeline)

  server.pending_jobs(pipeline).each do |job|
    runner = fleet.find_available_runner(job)
    if runner
      runner.assign_job(job)
      job.transition_to(:running)
      puts "[T+#{time}s] #{job.name} → #{runner.id}"
    end
  end

  time += 1
end

puts "Pipeline #{pipeline.status}"
```

### Custom Validation

```ruby
# Lint with custom error handling
result = Commands::LintCommand.execute(
  entry: 'custom-ci.yml',
  format: 'json'
)

if result.success?
  puts "Valid configuration"
else
  result.errors.each do |error|
    puts "ERROR: #{error}"
  end
  exit 1
end
```

### Variable Expansion

```ruby
# Expand variables with error mode
expander = VariableExpander.new(mode: :error)

begin
  script = expander.expand(
    'deploy.sh ${ENV} ${REGION}',
    { 'ENV' => 'prod', 'REGION' => 'us-east-1' }
  )
  puts "Expanded: #{script}"
rescue UndefinedVariableError => e
  puts "Missing variable: #{e.message}"
  exit 1
end
```

---

## See Also

- [Architecture Documentation](architecture.md)
- [Event Schema](event_schema.md)
- [Runner Format](runner_format.md)
