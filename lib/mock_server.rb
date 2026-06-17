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
    job_configs = extract_jobs(parsed_config)

    # GAP 4: workflow:rules:variables cascade. Variable assembly order:
    #   1. predefined CI_* vars (from PredefinedVariables.build)
    #   2. top-level `variables:` defaults
    #   3. trigger overlay (options[:variables])
    #   4. matched workflow.rules' `variables:` (if any)
    # The merged set is then visible to BOTH include-rules (already
    # evaluated upstream of MockServer in DryRunCommand) and per-job
    # rules. If `workflow:rules:` is present and NO rule matches, the
    # pipeline is empty — matches upstream EvaluateWorkflowRules.
    effective_vars = build_effective_variables(parsed_config, options[:variables] || {})
    workflow_result = apply_workflow_rules(parsed_config, effective_vars)
    effective_vars = workflow_result[:variables]

    if workflow_result[:filtered]
      warn 'Warning: workflow:rules: matched no rule, skipping pipeline'
      raise WorkflowRulesFilteredError, 'workflow:rules: matched no rule, skipping pipeline'
    end

    job_configs = filter_jobs_by_rules(job_configs, effective_vars)

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

  # Build the variables hash used to evaluate job-level `rules:`.
  #
  # GitLab makes top-level `variables:` defaults visible to job rules
  # (unlike include rules). Pipeline-trigger variables override defaults.
  #
  # @param config [Hash] Parsed (post-include, post-extends) configuration.
  # @param trigger_vars [Hash] Variables supplied at pipeline trigger time
  #   (e.g. via `--variables`).
  # @return [Hash<String, String>] Effective variable map.
  def build_effective_variables(config, trigger_vars)
    # GAP 3: predefined CI_* variables form the base layer.
    predefined = PredefinedVariables.build(
      project_dir: @project_dir, pipeline_source: @pipeline_source
    )

    defaults = predefined.dup
    raw = config['variables']
    if raw.is_a?(Hash)
      raw.each do |k, v|
        defaults[k.to_s] =
          if v.is_a?(Hash)
            # GitLab's `variables: FOO: { value: "...", description: "..." }` form.
            (v['value'] || v[:value] || '').to_s
          elsif v.nil?
            ''
          else
            v.to_s
          end
      end
    end

    # Trigger variables win over both predefined and defaults — matches
    # GitLab where dotenv / pipeline variables override predefined.
    trigger_vars.each { |k, v| defaults[k.to_s] = v.to_s }
    defaults
  end

  # GAP 4: Evaluate workflow.rules and cascade matched rule's `variables:`
  # into the pipeline variable set. Returns:
  #   { variables: Hash, filtered: Boolean }
  # filtered=true means workflow rules were present but matched nothing
  # — caller treats this as an empty pipeline.
  def apply_workflow_rules(config, variables)
    workflow = config['workflow'] || config[:workflow]
    rules = workflow.is_a?(Hash) ? (workflow['rules'] || workflow[:rules]) : nil
    return { variables: variables, filtered: false } if rules.nil?

    context = {
      project_dir: @project_dir,
      default_branch: variables['CI_DEFAULT_BRANCH'] || 'main'
    }

    result = RulesEvaluator.evaluate_rules(rules, variables, context: context, mode: :job)

    unless result[:matched]
      return { variables: variables, filtered: true }
    end

    # `when: never` on the matched workflow rule also filters the pipeline.
    if result[:when] && result[:when].to_s == 'never'
      return { variables: variables, filtered: true }
    end

    # Merge matched rule's `variables:` over the current set.
    matched_vars = result[:attributes]['variables']
    if matched_vars.is_a?(Hash)
      matched_vars.each { |k, v| variables[k.to_s] = v.to_s }
    end

    { variables: variables, filtered: false }
  end

  # Drop jobs whose `rules:` exclude them under the effective variables.
  #
  # A job is kept iff:
  #   - it has no `rules:` key, OR
  #   - the first matching rule's `when:` is not `never`.
  # A job whose rules contain no matching entry is dropped (matches GitLab).
  #
  # @param job_configs [Hash] Job name => job config (post-extends).
  # @param variables [Hash] Effective variables for rule evaluation.
  # @return [Hash] Filtered job_configs.
  def filter_jobs_by_rules(job_configs, variables)
    kept = {}
    job_configs.each do |name, job_config|
      rules = job_config['rules'] || job_config[:rules]
      if rules.nil?
        kept[name] = job_config
        next
      end

      # Per-job rule eval gets a job-specific CI_JOB_NAME / CI_JOB_STAGE
      # overlay so rules can reference them.
      job_vars = variables.dup
      job_vars['CI_JOB_NAME']  = name.to_s
      job_vars['CI_JOB_STAGE'] = (job_config['stage'] || job_config[:stage] || 'test').to_s

      context = {
        project_dir: @project_dir,
        default_branch: variables['CI_DEFAULT_BRANCH'] || 'main'
      }
      result = RulesEvaluator.evaluate_rules(rules, job_vars, context: context, mode: :job)
      next unless result[:matched]
      next if result[:when] && result[:when].to_s == 'never'

      kept[name] = apply_rule_attributes(job_config, result)
    end

    cascade_drop_orphaned_needs(kept)
  end

  # GAP 5: Merge attributes from the matched rule into the job config.
  # Rule values override job-level values (matches upstream semantics
  # where `rules:variables:` win over the job's own `variables:`).
  # `when:` is also surfaced on the job spec so downstream consumers can
  # see it (e.g. `manual`, `delayed`).
  def apply_rule_attributes(job_config, rule_result)
    merged = job_config.dup
    attrs = rule_result[:attributes] || {}

    if (rule_vars = attrs['variables']).is_a?(Hash)
      job_vars = merged['variables'].is_a?(Hash) ? merged['variables'].dup : {}
      rule_vars.each { |k, v| job_vars[k.to_s] = v }
      merged['variables'] = job_vars
    end

    %w[allow_failure start_in needs interruptible].each do |k|
      merged[k] = attrs[k] unless attrs[k].nil?
    end

    merged['when'] = rule_result[:when] if rule_result[:when]
    merged
  end

  # Repeatedly drop any job whose `needs:` reference a job not in the
  # current set, until a fixed point is reached. Matches GitLab's behavior:
  # a job whose needed dependency was rules-filtered out is itself dropped.
  # Names containing `/` (cross-pipeline / external-project needs) are
  # treated as out-of-scope and never orphan a job.
  #
  # @param job_configs [Hash] Surviving job_configs after direct rule filter.
  # @return [Hash] Job_configs with cascade-orphaned jobs removed.
  def cascade_drop_orphaned_needs(job_configs)
    loop do
      surviving = job_configs.keys
      orphaned = job_configs.select do |_name, cfg|
        needs = extract_needs(cfg['needs'])
        needs.any? { |n| !surviving.include?(n) && !n.include?('/') }
      end
      break if orphaned.empty?

      orphaned.each_key { |n| job_configs.delete(n) }
    end
    job_configs
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
