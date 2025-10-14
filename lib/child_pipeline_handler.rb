# frozen_string_literal: true

# Handles triggering of child pipelines from parent jobs
# Supports recursive pipeline invocation with variable passing
class ChildPipelineHandler
  attr_reader :max_depth

  DEFAULT_MAX_DEPTH = 10

  # Initialize the child pipeline handler
  #
  # @param max_depth [Integer] Maximum recursion depth for nested pipelines
  def initialize(max_depth: DEFAULT_MAX_DEPTH)
    @max_depth = max_depth
  end

  # Trigger a child pipeline from a parent job
  #
  # @param parent_job [MockJob] The parent job that triggers the child pipeline
  # @param downstream_config [Hash] Configuration for the downstream pipeline
  #   - :project - Project path for the child pipeline
  #   - :file - Path to the child pipeline config file (default: .gitlab-ci.yml)
  #   - :variables - Variables to pass to child pipeline
  #   - :strategy - Trigger strategy (depend, etc.)
  # @param current_depth [Integer] Current recursion depth
  # @return [Hash] Result of child pipeline execution
  def trigger_child(parent_job, downstream_config, current_depth: 0)
    # Fail-fast: Check depth limit
    if current_depth >= @max_depth
      raise "Child pipeline depth limit exceeded: #{current_depth} >= #{@max_depth}"
    end

    # Parse downstream configuration
    downstream_project = downstream_config[:project] || downstream_config['project']
    downstream_file = downstream_config[:file] || downstream_config['file'] || '.gitlab-ci.yml'
    downstream_vars = downstream_config[:variables] || downstream_config['variables'] || {}

    # Fail-fast: Validate required fields
    unless downstream_project
      raise "Child pipeline requires 'project' field in configuration"
    end

    # Merge variables: parent job variables + downstream variables
    merged_variables = (parent_job.variables || {}).merge(downstream_vars)

    # Build command arguments
    args = build_command_args(
      downstream_file,
      downstream_project,
      merged_variables,
      parent_job.id,
      current_depth + 1
    )

    # Spawn child process
    # Note: Using system() for simplicity; could use Process.spawn for more control
    output = `#{args.join(' ')} 2>&1`
    exit_code = $?.exitstatus
    success = exit_code.zero?

    # Emit event (if event system is available)
    emit_child_event(parent_job.id, downstream_project, success, exit_code)

    # Return result
    {
      success: success,
      exit_code: exit_code,
      output: output
    }
  end

  private

  # Build command arguments for child pipeline invocation
  #
  # @param downstream_file [String] Path to child config file
  # @param downstream_project [String] Path to child project
  # @param variables [Hash] Variables to pass
  # @param parent_job_id [String, Integer] Parent job ID
  # @param depth [Integer] Current depth
  # @return [Array<String>] Command arguments
  def build_command_args(downstream_file, downstream_project, variables, parent_job_id, depth)
    args = []

    # Find gitlab_ci_cli executable
    # Look for it in the project bin directory
    cli_path = File.expand_path('../../bin/gitlab_ci_cli', __dir__)
    args << cli_path

    # Command: dry-run (for now, could be extended)
    args << 'dry-run'

    # Entry file
    args << '--entry'
    args << File.join(downstream_project, downstream_file)

    # Project path (if different from current)
    args << '--project'
    args << downstream_project

    # Variables
    variables.each do |key, value|
      args << '--variables'
      args << "#{key}=#{value}"
    end

    # Metadata for child pipeline tracking
    args << '--parent-job-id'
    args << parent_job_id.to_s

    args << '--depth'
    args << depth.to_s

    args
  end

  # Emit event for child pipeline creation
  #
  # @param parent_job_id [String, Integer] Parent job ID
  # @param child_project [String] Child project path
  # @param success [Boolean] Whether child pipeline succeeded
  # @param exit_code [Integer] Exit code from child process
  def emit_child_event(parent_job_id, child_project, success, exit_code)
    # Event emission placeholder
    # In a full implementation, this would integrate with MockServer's event system
    # For now, we just log the event details
    event = {
      type: :child_pipeline_created,
      parent_job_id: parent_job_id,
      child_project: child_project,
      success: success,
      exit_code: exit_code,
      timestamp: Time.now
    }

    # Could emit to a global event bus or MockServer instance
    # For now, this is a no-op placeholder
    event
  end
end
