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

  attr_reader :event_queue

  # No GitLab checkout: the server is standalone. include:template is the
  # only consumer of one, and that lives in PipelineBuilder (TASK-43).
  #
  # @param project_dir [String] repository root (rules exists:/changes:)
  # @param pipeline_source [String] CI_PIPELINE_SOURCE
  def initialize(project_dir: nil, pipeline_source: 'push')
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

  # Create a pipeline from a config that has not been through
  # PipelineBuilder (YAML string or parsed hash; no includes/extends):
  # applies default:/inherit:, expands parallel:, evaluates workflow and job rules, then
  # create_pipeline_from.
  #
  # @param config [String, Hash] YAML config content or parsed hash
  # @param options [Hash] :ref, :variables (CLI/trigger variables)
  # @return [MockPipeline] Created pipeline object
  # @raise [WorkflowRulesFilteredError] workflow:rules created no pipeline
  def create_pipeline(config, options = {})
    parsed_config = parse_configuration(config)
    job_definitions, errors = PipelineBuilder.expand_parallel(PipelineBuilder.compose_jobs(parsed_config))
    errors = PipelineBuilder.stage_errors(job_definitions, extract_stages(parsed_config)) if errors.empty?
    raise ConfigurationError, "Configuration errors:\n  - #{errors.join("\n  - ")}" unless errors.empty?

    evaluated = PipelineBuilder.evaluate_rules(
      parsed_config,
      jobs: PipelineBuilder.visible_jobs(job_definitions),
      predefined: PredefinedVariables.build(project_dir: @project_dir, pipeline_source: @pipeline_source),
      cli_variables: options[:variables] || {},
      project_dir: @project_dir
    )
    raise WorkflowRulesFilteredError, PipelineBuilder::WORKFLOW_SKIPPED_MESSAGE if evaluated[:workflow_skipped]

    create_pipeline_from(
      stages: extract_stages(parsed_config),
      jobs: evaluated[:pipeline_jobs],
      ref: options[:ref],
      variables: options[:variables]
    )
  end

  # Create a pipeline from jobs already resolved and rule-filtered
  # (PipelineBuilder::Result#pipeline_jobs).
  #
  # @param stages [Array<String>]
  # @param jobs [Hash] job name => job config
  # @return [MockPipeline]
  def create_pipeline_from(stages:, jobs:, ref: nil, variables: nil)
    raise ConfigurationError, "No jobs defined in configuration" if jobs.empty?

    validate_job_configs(jobs)
    validate_dag(jobs)

    @pipeline_counter += 1
    pipeline = MockPipeline.new(
      id: @pipeline_counter,
      stages: stages,
      jobs: jobs,
      ref: ref || 'HEAD',
      variables: variables || {}
    )
    @pipelines[pipeline.id] = pipeline

    emit_event(EVENT_PIPELINE_CREATED, {
      pipeline_id: pipeline.id,
      stages: stages,
      job_count: jobs.size
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
    PipelineBuilder.stages(config)
  end

  # Validate job configurations
  #
  # Stages are checked before rules, by PipelineBuilder.stage_errors.
  #
  # @param job_configs [Hash] Job configurations
  def validate_job_configs(job_configs)
    errors = []

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
        unless CiKeywords::JOB.include?(key_str)
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
                   when MockPipeline::STATE_SUCCESS, MockPipeline::STATE_FAILED, :skipped, :canceled
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
