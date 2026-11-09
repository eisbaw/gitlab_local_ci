# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'yaml'
require_relative 'mock_pipeline'
require_relative 'rules_evaluator'
require_relative 'predefined_variables'
require_relative 'pipeline_builder'

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

  attr_reader :gitlab_path, :event_queue

  # Initialize the mock server with a path to the GitLab submodule
  #
  # @param gitlab_path [String] Path to the GitLab CE git submodule (not used in standalone mode)
  def initialize(gitlab_path = nil, project_dir: nil, pipeline_source: 'push')
    # Validate gitlab_path if provided and not empty
    if gitlab_path && !gitlab_path.empty? && !Dir.exist?(gitlab_path)
      raise ArgumentError, "GitLab lib directory not found at: #{gitlab_path}"
    end

    @gitlab_path = gitlab_path
    @event_queue = []
    @pipelines = {}
    @pipeline_counter = 0
    @project_dir = File.expand_path(project_dir || Dir.pwd)
    @pipeline_source = pipeline_source
  end

  # Signals to caller that workflow:rules: produced no match and the
  # pipeline must be empty (matches upstream
  # Ci::Pipeline.workflow_rules_failure_message).
  class WorkflowRulesFilteredError < StandardError; end

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
    job_configs = PipelineBuilder.visible_jobs(parsed_config)

    # GAP 4: workflow:rules:variables cascade. Variable assembly order:
    #   1. predefined CI_* vars (from PredefinedVariables.build)
    #   2. top-level `variables:` defaults
    #   3. trigger overlay (options[:variables])
    #   4. matched workflow.rules' `variables:` (if any)
    # The merged set is then visible to BOTH include-rules (already
    # evaluated upstream of MockServer in DryRunCommand) and per-job
    # rules. If `workflow:rules:` is present and NO rule matches, the
    # pipeline is empty — matches upstream EvaluateWorkflowRules.
    effective_vars = PipelineBuilder.pipeline_variables(
      parsed_config,
      predefined: PredefinedVariables.build(project_dir: @project_dir, pipeline_source: @pipeline_source),
      cli_variables: options[:variables] || {}
    )
    workflow_result = PipelineBuilder.apply_workflow_rules(parsed_config, effective_vars, project_dir: @project_dir)
    effective_vars = workflow_result[:variables]

    if workflow_result[:filtered]
      warn 'Warning: workflow:rules: matched no rule, skipping pipeline'
      raise WorkflowRulesFilteredError, 'workflow:rules: matched no rule, skipping pipeline'
    end

    job_configs = PipelineBuilder.filter_jobs_by_rules(job_configs, effective_vars, project_dir: @project_dir)

    # Validate there are jobs
    if job_configs.empty?
      raise ConfigurationError, "No jobs defined in configuration"
    end

    # Validate job configurations
    validate_job_configs(job_configs)

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

  # Validate job configurations
  #
  # @param job_configs [Hash] Job configurations
  def validate_job_configs(job_configs)
    errors = []

    # Known valid job keys
    valid_keys = %w[
      script before_script after_script stage image services
      artifacts cache dependencies variables tags when
      allow_failure retry timeout parallel extends needs rules
      environment coverage resource_group release inherit
      interruptible only except trigger pages
    ]

    job_configs.each do |job_name, job_config|
      # Validate script is present (unless trigger or pages is defined)
      script = job_config['script'] || job_config[:script]
      trigger = job_config['trigger'] || job_config[:trigger]
      pages = job_config['pages'] || job_config[:pages]

      if script.nil? && trigger.nil? && pages.nil?
        errors << "Job '#{job_name}' is missing required 'script' field"
      elsif script.is_a?(Array) && script.empty?
        errors << "Job '#{job_name}' has empty 'script' array"
      end

      # Check for unknown keys
      job_config.each_key do |key|
        key_str = key.to_s
        unless valid_keys.include?(key_str)
          errors << "Job '#{job_name}' has unknown key: '#{key_str}'"
        end
      end
    end

    unless errors.empty?
      raise ConfigurationError, "Configuration errors:\n  - #{errors.join("\n  - ")}"
    end
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
        raise ConfigurationError, "circular dependency detected involving job '#{job_name}'"
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
      needs = PipelineBuilder.needs_job_names(job_config['needs'])

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
  # @return [Boolean] True if state changed since last call
  def process_pipeline(pipeline)
    # Check if status has changed (pipeline tracks its own previous state)
    # Note: Job state transitions are managed externally (e.g., by DryRunCommand)
    # This method only observes state changes and emits events
    status_change = pipeline.status_changed?

    if status_change
      new_status = status_change[:new]

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
