# gitlab_ci_cli Implementation Tasks

## Project Setup & Infrastructure ✅ DONE
Create project directory structure
Create shell.nix file with Nix environment configuration
Add Ruby 3.0+ to shell.nix
Add Git 2.25+ to shell.nix
Add Bundler to shell.nix
Add Graphviz to shell.nix
Add just command runner to shell.nix
Add RSpec to shell.nix
Create .gitignore file
Add common Ruby ignore patterns to .gitignore
Add Nix ignore patterns to .gitignore
Create .gitmodules file pointing to gitlab.com/gitlab-org/gitlab
Initialize GitLab CE git submodule
Pin GitLab submodule to specific stable version tag
Create lib/ directory
Create spec/ directory
Create bin/ directory
Create runners/ directory for mock runner configs
Create Gemfile for Ruby dependencies
Add rspec gem to Gemfile
Add gitlab gem to Gemfile for API client
Bundle install to generate Gemfile.lock

## Justfile Workflow Commands ✅ DONE
Create justfile with header comments
Add help command to justfile (list all commands)
Add shell command to justfile (enter nix-shell)
Add setup command to justfile (git submodule init + bundle install)
Add test command to justfile (run rspec)
Add test-file command to justfile (run specific test file)
Add lint command to justfile (validate YAML)
Add dag command to justfile (generate DOT graph)
Add dry-run command to justfile (simulate pipeline)
Add update-gitlab command to justfile (update submodule)
Add clean command to justfile (remove temp files)
Add test-integration command to justfile (run integration tests)

## Core Executable & Entry Point ✅ DONE
Create bin/gitlab_ci_cli executable file
Add shebang line to bin/gitlab_ci_cli
Make bin/gitlab_ci_cli executable (chmod +x)
Create lib/gitlab_ci_cli.rb main entry point
Add GitLab lib path to Ruby load path
Create lib/version.rb with VERSION constant
Implement basic CLI argument parser
Add --help flag implementation
Add --version flag implementation
Add --entry flag to specify .gitlab-ci.yml path
Add --project flag to specify project directory
Add --runners flag to specify runner fleet directory
Add --ref flag to specify git reference
Add --pipeline flag to specify pipeline type
Add --variables flag to set CI variables (repeatable)
Add --env flag as alias for --variables
Add --undefined flag to set undefined variable handling mode
Add --verbose flag for increased output
Add --format flag for output format (text/json/junit)
Add --gitlab-dir flag to specify GitLab submodule path
Implement command routing (lint/dag/dry-run/help)
Add error handling for missing commands
Add error handling for invalid flags

## Module 1: Mock GitLab Server ✅ DONE
Create lib/mock_server.rb file
Define MockServer class
Add initialize method with gitlab_path parameter
Add GitLab upstream classes to load path
Require Gitlab::Ci::YamlProcessor
Require Gitlab::Ci::Config
Require Gitlab::Ci::Config::Entry modules
Create event emission infrastructure
Define event types as constants (job_assigned, job_started, job_completed, etc.)
Implement emit_event method
Create event queue/buffer
Implement JobDispatcher class within MockServer
Implement intercept_job_request method
Implement find_eligible_job method using upstream logic
Implement build_job_payload method
Wrap Gitlab::Ci::YamlProcessor for YAML parsing
Create mock_project method to satisfy upstream requirements
Wrap Ci::CreatePipelineService for pipeline creation
Wrap Ci::ProcessPipelineService for state transitions
Wrap Ci::RegisterJobService for job scheduling
Implement validate_dag method using Gitlab::Ci::YamlProcessor::Dag
Add circular dependency detection
Implement create_pipeline method
Parse YAML config using YamlProcessor
Extract stages from processor result
Extract jobs from processor result
Build pipeline object with stages and jobs
Implement process_pipeline method for state transitions
Track pipeline state (pending, running, completed)
Implement has_pending_jobs? predicate
Implement pending_jobs accessor
Add unit tests for MockServer initialization
Test YAML parsing with valid config
Test YAML parsing with invalid config
Test circular dependency detection
Test pipeline creation
Test job scheduling algorithm

## Module 2: Runner Fleet Manager ✅ DONE
Create lib/runner_fleet.rb file
Define RunnerFleet class
Implement initialize method
Implement load_runners method with directory parameter
Use Dir.glob to find all *.json files in runners directory
Parse each JSON file
Validate JSON structure
Create MockRunner instance for each config
Store runners in instance variable
Implement find_available_runner method
Check runner tag compatibility with job
Check runner capacity availability
Return first matching available runner
Return nil if no runner available
Implement runners accessor method
Create example runner JSON files
Create runners/runner1.json with minimal format
Create runners/runner2.json with different tags
Create runners/runner3.json with extended format
Add unit tests for RunnerFleet
Test loading runners from directory
Test finding available runner by tags
Test finding available runner with capacity check
Test no available runner scenario

## Module 3: Mock Runner Client ✅ DONE
Create lib/mock_runner.rb file
Define MockRunner class
Implement initialize method with runner_data hash
Parse runner id from JSON
Parse runner tags from JSON
Parse runner executor from JSON
Parse runner max_jobs from JSON
Store runner configuration
Initialize running_jobs counter
Implement can_handle? method
Check if runner tags match job requirements
Handle run_untagged flag
Handle locked/protected runners
Return boolean result
Implement has_capacity? method
Compare running_jobs with max_jobs
Return boolean result
Implement assign_job method
Increment running_jobs counter
Store job reference
Emit job_assigned event
Implement handle_job_assignment method
Extract job payload from event
Log runner ID and job ID
Log project name
Log stage name
Log job name
Log script commands
Log Docker image if present
Log services if present
Log artifacts if present
Emit job_started event
Emit job_completed event with success status
Implement release_job method
Decrement running_jobs counter
Remove job reference
Add unit tests for MockRunner
Test can_handle with matching tags
Test can_handle with non-matching tags
Test has_capacity when under limit
Test has_capacity when at limit
Test assign_job increments counter
Test release_job decrements counter

## Mock Job Class ✅ DONE
Create lib/mock_job.rb file
Define MockJob class
Implement initialize with job data
Store job ID
Store job name
Store job stage
Store job script
Store job image
Store job services
Store job artifacts
Store job variables
Store job tag_list
Initialize job status as :pending
Implement transition_to method
Validate state transitions
Update status
Emit state change event
Implement pending? predicate
Implement running? predicate
Implement completed? predicate
Implement failed? predicate
Add unit tests for MockJob state machine

## CLI Commands: Lint ✅ DONE
Implement lint_command method
Accept options hash parameter
Read YAML file from options[:entry]
Create Gitlab::Ci::YamlProcessor instance
Pass mock project to processor
Pass git ref to processor
Check if processor.valid?
If valid: output success message
If valid: output stages list
If valid: output job count
If valid: exit with status 0
If invalid: output error message
If invalid: iterate processor.errors
If invalid: output each error with prefix
If invalid: exit with status 1
Handle file not found error
Handle YAML syntax errors
Add --format support to lint command
Implement text format output
Implement JSON format output
Implement JUnit format output
Add unit tests for lint_command
Test with valid YAML
Test with invalid YAML
Test with missing file
Test with syntax errors
Test text format output
Test JSON format output

## CLI Commands: DAG ✅ DONE
Implement dag_command method
Accept options hash parameter
Create mock pipeline from options
Initialize Graphviz DOT output
Output digraph header
Set rankdir="LR" attribute
Iterate pipeline stages
For each stage: create subgraph cluster
For each stage: set label
For each stage: add jobs as nodes
Iterate jobs with needs dependencies
For each job: iterate needs
For each need: add edge from need to job
Close subgraph blocks
Output closing brace
Handle circular dependency errors
Catch Gitlab::Ci::YamlProcessor::Dag::CircularDependencyError
Output error message with details
Exit with status 1
Add unit tests for dag_command
Test simple linear pipeline
Test pipeline with parallel stages
Test pipeline with needs dependencies
Test circular dependency detection
Test DOT output format validation

## CLI Commands: Dry Run ✅ DONE
Implement dry_run_command method
Accept options hash parameter
Initialize MockServer with gitlab_path
Load RunnerFleet from options[:runners]
Read config file from options[:entry]
Parse variables from options[:variables]
Create pipeline via server.create_pipeline
Output pipeline ID and job count
Initialize time counter
Enter main scheduling loop
While pipeline has pending jobs:
  Call server.process_pipeline
  Iterate pipeline.pending_jobs
  For each job: find available runner from fleet
  If runner found: output job assignment message
  If runner found: assign job to runner
  If runner found: transition job to running
  If no runner: output waiting message
  Increment time counter
  Break if infinite loop detected
Output pipeline completion status
Exit with appropriate status code
Add simulation timeout parameter
Add --timeout flag
Handle timeout gracefully
Add unit tests for dry_run_command
Test successful pipeline execution
Test job waiting for runner availability
Test runner capacity exhaustion
Test pipeline failure scenarios

## Variable Handling ✅ DONE
Create lib/variable_expander.rb file
Define VariableExpander class
Implement initialize with mode parameter
Accept :warning mode
Accept :error mode
Accept :empty mode
Store mode in instance variable
Implement expand method
Accept text string parameter
Accept variables hash parameter
Use regex to match ${VAR} syntax
Use regex to match $VAR syntax
For each match: check if variable defined
If defined: replace with variable value
If undefined and mode=:warning: output warning and keep original
If undefined and mode=:error: raise UndefinedVariableError
If undefined and mode=:empty: replace with empty string
Return expanded text
Create UndefinedVariableError class
Add error message with variable name
Parse --variables flags from CLI
Split on = to extract key and value
Build variables hash
Pass to pipeline creation
Integrate VariableExpander in pipeline creation
Use mode from --undefined flag
Add unit tests for VariableExpander
Test with defined variables
Test with undefined variables in warning mode
Test with undefined variables in error mode
Test with undefined variables in empty mode
Test ${VAR} syntax
Test $VAR syntax
Test multiple variables in single string

## Child Pipeline Support 📝 STUB (needs implementation)
Create lib/child_pipeline_handler.rb file
Define ChildPipelineHandler class
Implement trigger_child method
Accept parent_job parameter
Accept downstream_config parameter
Parse downstream project from config
Parse downstream file from config (default .gitlab-ci.yml)
Serialize parent job variables
Build gitlab_ci_cli command arguments
Add --entry flag with downstream file
Add --project flag with downstream project path
Add --variables flags with parent variables
Add --pipeline flag with parent_pipeline type
Add --parent-job-id flag with parent job ID
Spawn child process using Process.spawn
Wait for child process completion using Process.wait
Capture exit status from $?
Emit child_pipeline_created event
Include parent_job.id in event
Include child_project name in event
Include success/failure status in event
Return child pipeline result
Detect trigger jobs in pipeline processing
Check job configuration for trigger keyword
Call ChildPipelineHandler when trigger detected
Add unit tests for ChildPipelineHandler
Test child pipeline invocation
Test variable passing to child
Test child success handling
Test child failure handling
Test recursive pipeline depth

## Include Processing 📝 STUB (needs implementation)
Create lib/include_processor.rb file
Define IncludeProcessor class
Define INCLUDE_TYPES constant array
Add :local to INCLUDE_TYPES
Add :file to INCLUDE_TYPES
Add :remote to INCLUDE_TYPES
Add :template to INCLUDE_TYPES
Add :project to INCLUDE_TYPES
Add :component to INCLUDE_TYPES
Define MAX_DEPTH constant (150)
Implement process_includes method
Accept config hash parameter
Accept depth parameter (default 0)
Check if depth > MAX_DEPTH
If exceeded: raise IncludeDepthExceededError
Extract includes array from config
Handle single include (convert to array)
Iterate each include_spec
Determine include type
Call appropriate fetch method for type
Implement fetch_local_include
Implement fetch_file_include
Implement fetch_remote_include
Implement fetch_template_include
Implement fetch_project_include
Implement fetch_component_include
Parse fetched content as YAML
Implement deep_merge method
Merge included config into main config
Recursively call process_includes on merged config
Increment depth counter
Return final merged config
Create IncludeDepthExceededError class
Add unit tests for IncludeProcessor
Test local include processing
Test remote include processing
Test template include processing
Test depth limit enforcement
Test circular include detection
Test include type detection

## Output Formatting ✅ DONE
Create lib/formatters directory
Create lib/formatters/base_formatter.rb
Define BaseFormatter abstract class
Define format method signature
Create lib/formatters/text_formatter.rb
Define TextFormatter class inheriting BaseFormatter
Implement format method for text output
Format lint results as text
Format dag results as text
Format dry-run results as text
Create lib/formatters/json_formatter.rb
Define JsonFormatter class inheriting BaseFormatter
Implement format method for JSON output
Convert lint results to JSON
Convert dag results to JSON
Convert dry-run results to JSON
Create lib/formatters/junit_formatter.rb
Define JunitFormatter class inheriting BaseFormatter
Implement format method for JUnit XML output
Generate JUnit XML structure
Add testsuite elements
Add testcase elements
Add failure elements for errors
Implement formatter factory method
Accept format string (text/json/junit)
Return appropriate formatter instance
Integrate formatters into commands
Update lint_command to use formatter
Update dag_command to use formatter
Update dry_run_command to use formatter
Add unit tests for formatters
Test text formatter output
Test JSON formatter output
Test JUnit formatter output
Test invalid format handling

## Runner Exporter Tool 📝 STUB (needs implementation)
Create lib/runner_exporter.rb file
Define RunnerExporter class
Implement initialize method
Implement export_from_gitlab method
Accept gitlab_url parameter
Accept token parameter
Create Gitlab API client instance
Set endpoint to gitlab_url
Set private_token to token
Fetch runners via client.runners
Set per_page to 100
Handle pagination
Iterate each runner
Convert runner to hash
Convert hash to JSON
Write to runners/runner_{id}.json file
Output progress messages
Handle API errors
Handle network errors
Handle authentication errors
Create CLI command for runner export
Add export-runners subcommand
Add --url flag for GitLab URL
Add --token flag for API token
Add --output-dir flag for runner directory
Call RunnerExporter.export_from_gitlab
Add unit tests for RunnerExporter (with mocked API)

## Testing Infrastructure 🚧 IN PROGRESS (tests exist, benchmarks needed)
Create spec/spec_helper.rb
Require rspec
Configure RSpec
Add helper methods
Set up test load paths
Create spec/support directory
Create spec/support/fixtures.rb
Define fixture loading helpers
Create spec/fixtures directory
Create spec/fixtures/yaml directory
Create spec/fixtures/yaml/valid_simple.yml
Create spec/fixtures/yaml/valid_with_needs.yml
Create spec/fixtures/yaml/invalid_syntax.yml
Create spec/fixtures/yaml/circular_dependency.yml
Create spec/fixtures/runners directory
Create spec/fixtures/runners/docker_runner.json
Create spec/fixtures/runners/shell_runner.json
Create .rspec configuration file
Set --require spec_helper
Set --color
Set --format documentation
Create spec/unit directory
Create spec/integration directory
Set up GitLab version matrix testing
Test against GitLab 15.0
Test against GitLab 16.0
Test against GitLab 17.0
Add code coverage with SimpleCov
Configure coverage thresholds (90%)
Create spec/unit/mock_server_spec.rb
Test MockServer initialization
Test YAML parsing
Test pipeline creation
Test event emission
Create spec/unit/runner_fleet_spec.rb
Test loading runners from directory
Test finding available runner
Test runner capacity checks
Create spec/unit/mock_runner_spec.rb
Test tag matching
Test capacity checking
Test job assignment
Create spec/unit/variable_expander_spec.rb
Test variable expansion modes
Test undefined variable handling
Create spec/integration/lint_spec.rb
Test lint command with valid YAML
Test lint command with invalid YAML
Test lint command with missing file
Create spec/integration/dag_spec.rb
Test DAG generation
Test circular dependency detection
Create spec/integration/dry_run_spec.rb
Test full pipeline simulation
Test runner assignment
Test job scheduling

## Performance Optimization
Create benchmarking test suite
Create spec/benchmarks directory
Create spec/benchmarks/large_pipeline_spec.rb
Test with 100-job pipeline
Test with 1000-job pipeline
Measure execution time
Create spec/benchmarks/runner_fleet_spec.rb
Test with 10-runner fleet
Test with 100-runner fleet
Measure runner matching performance
Profile YAML parsing
Identify bottlenecks
Add caching for repeated YAML parses
Profile pipeline creation
Identify bottlenecks
Optimize DAG construction
Profile runner matching algorithm
Optimize tag matching
Add early exit conditions
Profile memory usage
Use memory profiler gem
Identify memory leaks
Optimize data structures
Add lazy evaluation where possible
Defer loading GitLab modules until needed

## Documentation
Create README.md
Add project title and description
Add features list
Add installation section with nix-shell instructions
Add quick start guide
Add usage examples for lint command
Add usage examples for dag command
Add usage examples for dry-run command
Document all CLI flags
Add troubleshooting section
Add GitLab version compatibility table
Add license information
Add contributing section
Create CONTRIBUTING.md
Add code style guidelines
Add testing requirements
Add PR submission process
Add development setup instructions
Document how to run tests
Document how to update GitLab submodule
Create LICENSE file
Add Apache 2.0 license text
Create docs/ directory
Create docs/architecture.md
Document three-module design
Add architecture diagrams
Document event-driven approach
Document GitLab integration strategy
Create docs/event_schema.md
Document all event types
Add event payload examples
Create docs/runner_format.md
Document JSON runner format
Add examples for all runner types
Create docs/upgrade_guide.md
Document GitLab version upgrade process
Add compatibility matrix
Document breaking changes
Create docs/api_reference.md
Document all public classes
Document all public methods
Add usage examples
Add inline YARD documentation
Document MockServer class
Document RunnerFleet class
Document MockRunner class
Document VariableExpander class
Document IncludeProcessor class

## Release Preparation
Create CHANGELOG.md
Add unreleased section
Document all features
Document all bug fixes
Create version tagging strategy
Create release checklist
Verify all tests pass
Verify code coverage meets threshold
Verify documentation is complete
Verify examples work
Create GitHub release workflow
Tag version
Generate release notes
Attach binaries if applicable
Publish to RubyGems if applicable
Create Docker image if applicable

## Security & Compliance
Review code for security issues
Check for shell injection vulnerabilities
Check for path traversal vulnerabilities
Check for code injection vulnerabilities
Validate all user inputs
Sanitize file paths
Sanitize command arguments
Add security policy document
Document vulnerability reporting process
Add dependabot configuration
Enable automated security updates
Review GitLab submodule license (Apache 2.0)
Ensure license compatibility
Add license headers to source files
Review data privacy considerations
Document what data is collected (none)
Document what data is transmitted (none)
