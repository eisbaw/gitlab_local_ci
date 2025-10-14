# frozen_string_literal: true

require 'yaml'
require_relative 'mock_pipeline'

# MockServer simulates GitLab's CI pipeline server functionality
# It parses YAML configs, creates pipelines, and manages job scheduling
# while emitting events for external consumption.
#
# MPED Principles:
# - Standalone: No GitLab dependencies, pure Ruby + YAML
# - Event-driven: Emits events for pipeline lifecycle
# - Stateless: Each pipeline is independent
# - Fail-fast: Validates configuration before creating pipeline
class MockServer
  # Event type constants
  EVENT_JOB_ASSIGNED = :job_assigned
  EVENT_JOB_STARTED = :job_started
  EVENT_JOB_COMPLETED = :job_completed
  EVENT_JOB_FAILED = :job_failed
  EVENT_PIPELINE_CREATED = :pipeline_created
  EVENT_PIPELINE_STARTED = :pipeline_started
  EVENT_PIPELINE_COMPLETED = :pipeline_completed

  # Reserved GitLab CI keywords (not job names)
  RESERVED_KEYWORDS = %w[
    stages variables include default workflow
    before_script after_script cache image services
  ].freeze

  attr_reader :gitlab_path, :event_queue

  # Initialize the mock server with a path to the GitLab submodule
  #
  # @param gitlab_path [String] Path to the GitLab CE git submodule (not used in standalone mode)
  def initialize(gitlab_path = nil)
    @gitlab_path = gitlab_path
    @event_queue = []
    @pipelines = {}
    @pipeline_counter = 0
  end

  # Create a pipeline from a YAML configuration
  #
  # @param config [String, Hash] YAML config content or parsed hash
  # @param options [Hash] Pipeline creation options (ref, variables, etc.)
  # @return [MockPipeline] Created pipeline object
  def create_pipeline(config, options = {})
    # Parse configuration
    parsed_config = parse_configuration(config)

    # Extract stages and jobs
    stages = extract_stages(parsed_config)
    job_configs = extract_jobs(parsed_config)

    # Validate there are jobs
    if job_configs.empty?
      raise ConfigurationError, "No jobs defined in configuration"
    end

    # Validate DAG for circular dependencies
    validate_dag(job_configs)

    # Build pipeline object
    # MockPipeline will convert job_configs to MockJob objects internally
    @pipeline_counter += 1
    pipeline = MockPipeline.new(
      id: @pipeline_counter,
      stages: stages,
      jobs: job_configs,
      ref: options[:ref] || 'HEAD',
      variables: options[:variables] || {}
    )

    @pipelines[pipeline.id] = pipeline

    # Emit creation event
    emit_event(EVENT_PIPELINE_CREATED, {
      pipeline_id: pipeline.id,
      stages: stages,
      job_count: job_configs.size
    })

    pipeline
  end

  # Configuration error class
  class ConfigurationError < StandardError; end

  private

  # Parse YAML configuration
  #
  # @param config [String, Hash] YAML content or parsed hash
  # @return [Hash] Parsed configuration
  def parse_configuration(config)
    case config
    when String
      YAML.safe_load(config, permitted_classes: [Symbol], aliases: true)
    when Hash
      config
    else
      raise ConfigurationError, "Configuration must be String (YAML) or Hash"
    end
  rescue Psych::SyntaxError => e
    raise ConfigurationError, "YAML syntax error: #{e.message}"
  rescue StandardError => e
    raise ConfigurationError, "Failed to parse configuration: #{e.message}"
  end

  # Extract stages from configuration
  #
  # @param config [Hash] Parsed configuration
  # @return [Array<String>] List of stages
  def extract_stages(config)
    config['stages'] || %w[build test deploy]
  end

  # Extract jobs from configuration
  #
  # Jobs are top-level keys that are not reserved keywords
  #
  # @param config [Hash] Parsed configuration
  # @return [Hash] Job name => job config
  def extract_jobs(config)
    jobs = {}

    config.each do |key, value|
      # Skip reserved keywords
      next if RESERVED_KEYWORDS.include?(key)

      # Skip non-hash values
      next unless value.is_a?(Hash)

      # Skip hidden jobs (templates starting with .)
      next if key.start_with?('.')

      jobs[key] = value
    end

    jobs
  end

  # Extract needs dependencies
  #
  # @param needs_config [Array, nil] Needs configuration
  # @return [Array<String>] List of job names
  def extract_needs(needs_config)
    return [] if needs_config.nil?
    return [] unless needs_config.is_a?(Array)

    needs_config.map do |need|
      case need
      when String
        need
      when Hash
        need['job']
      else
        nil
      end
    end.compact
  end

  # Validate pipeline DAG for circular dependencies
  #
  # Uses depth-first search to detect cycles
  #
  # @param job_configs [Hash] Job configurations
  def validate_dag(job_configs)
    visited = {}
    rec_stack = {}

    job_configs.each_key do |job_name|
      next if visited[job_name]

      if has_cycle?(job_name, job_configs, visited, rec_stack)
        raise ConfigurationError, "Circular dependency detected involving job '#{job_name}'"
      end
    end
  end

  # Detect cycle using DFS
  #
  # @param job_name [String] Current job being checked
  # @param job_configs [Hash] All job configurations
  # @param visited [Hash] Tracking of visited nodes
  # @param rec_stack [Hash] Tracking of recursion stack
  # @return [Boolean] true if cycle detected
  def has_cycle?(job_name, job_configs, visited, rec_stack)
    visited[job_name] = true
    rec_stack[job_name] = true

    job_config = job_configs[job_name]
    if job_config && job_config['needs']
      needs = extract_needs(job_config['needs'])

      needs.each do |dependency|
        next unless job_configs[dependency]

        if !visited[dependency]
          return true if has_cycle?(dependency, job_configs, visited, rec_stack)
        elsif rec_stack[dependency]
          # Found a back edge - cycle detected
          return true
        end
      end
    end

    # Remove from recursion stack before returning
    rec_stack[job_name] = false
    false
  end

  public

  # Process pipeline state transitions
  # Determines pipeline status based on job states and emits events
  #
  # @param pipeline [MockPipeline] Pipeline to process
  # @return [Boolean] True if state changed
  def process_pipeline(pipeline)
    old_status = pipeline.status

    # Determine new status based on job states
    new_status = if pipeline.has_pending_jobs?
                   if pipeline.status == MockPipeline::STATE_PENDING
                     MockPipeline::STATE_RUNNING
                   else
                     pipeline.status
                   end
                 else
                   # No pending jobs - pipeline complete
                   MockPipeline::STATE_SUCCESS
                 end

    if new_status != old_status
      pipeline.transition_to(new_status)

      # Emit appropriate event
      event_type = case new_status
                   when MockPipeline::STATE_RUNNING
                     EVENT_PIPELINE_STARTED
                   when MockPipeline::STATE_SUCCESS, MockPipeline::STATE_FAILED
                     EVENT_PIPELINE_COMPLETED
                   end

      emit_event(event_type, { pipeline_id: pipeline.id, status: new_status }) if event_type

      true
    else
      false
    end
  end

  # Check if the pipeline has pending jobs
  # Delegates to pipeline object
  #
  # @param pipeline [MockPipeline] Pipeline to check
  # @return [Boolean] True if there are pending jobs
  def has_pending_jobs?(pipeline)
    pipeline.has_pending_jobs?
  end

  # Get list of pending jobs in the pipeline
  # Returns jobs that are ready to run (dependencies satisfied)
  #
  # @param pipeline [MockPipeline] Pipeline to query
  # @return [Array<MockJob>] Array of job objects
  def pending_jobs(pipeline)
    pipeline.pending_jobs
  end

  # Emit an event to the event queue
  #
  # @param event_type [Symbol] Type of event (use EVENT_* constants)
  # @param payload [Hash] Event payload data
  def emit_event(event_type, payload = {})
    event = {
      type: event_type,
      timestamp: Time.now,
      payload: payload
    }
    @event_queue << event
  end
end
