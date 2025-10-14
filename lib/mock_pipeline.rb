# frozen_string_literal: true

require_relative 'mock_job'

# MockPipeline represents a pipeline created from GitLab CI configuration
# It holds stages, jobs, and state without requiring a database
#
# MPED Principles:
# - Single source of truth: @jobs array is the only mutable state
# - No derived state stored: status computed on demand from job states
# - Explicit state: pipeline status derived from job states
# - Immutable where possible: stages and ref are frozen after creation
class MockPipeline
  attr_reader :id, :stages, :jobs, :ref, :variables

  # Pipeline states
  STATE_PENDING = :pending
  STATE_RUNNING = :running
  STATE_SUCCESS = :success
  STATE_FAILED = :failed

  # Initialize pipeline with parsed configuration data
  #
  # @param id [Integer] Pipeline ID
  # @param stages [Array<String>] Ordered list of stage names
  # @param jobs [Hash] Hash of job name to job configuration (from GitLab YamlProcessor)
  # @param ref [String] Git reference (branch/tag/commit)
  # @param variables [Hash] Pipeline variables
  def initialize(id:, stages:, jobs:, ref:, variables:)
    @id = id
    @stages = stages.freeze
    @ref = ref.freeze
    @variables = variables.dup.freeze

    # Convert job hash to MockJob instances
    @jobs = build_mock_jobs(jobs)

    # Validate job dependencies
    validate_job_needs
  end

  # Get pipeline status based on job states
  # Status is derived, not stored - single source of truth principle
  #
  # @return [Symbol] Current pipeline status
  def status
    return STATE_PENDING if @jobs.all?(&:pending?)
    return STATE_RUNNING if @jobs.any?(&:running?)
    return STATE_FAILED if @jobs.any?(&:failed?)
    return STATE_SUCCESS if @jobs.all?(&:completed?)

    # Mixed state: some finished, some not
    STATE_RUNNING
  end

  # Check if pipeline has pending jobs
  #
  # @return [Boolean] True if any jobs are pending
  def has_pending_jobs?
    @jobs.any?(&:pending?)
  end

  # Get list of pending jobs that are ready to run
  # A job is ready if its dependencies (needs) are satisfied
  #
  # @return [Array<MockJob>] Array of pending jobs with satisfied dependencies
  def pending_jobs
    @jobs.select do |job|
      job.pending? && dependencies_satisfied?(job)
    end
  end

  # Transition pipeline to new state
  # Note: status is derived from jobs, but this method allows event emission
  #
  # @param new_status [Symbol] New status (STATE_* constants)
  def transition_to(new_status)
    # This is a no-op for derived status, but kept for API compatibility
    # Real status comes from job states
    # This method exists for event emission hooks
  end

  # Find a job by name
  #
  # @param name [String] Job name
  # @return [MockJob, nil] Job or nil if not found
  def find_job(name)
    @jobs.find { |job| job.name == name }
  end

  private

  # Build MockJob instances from GitLab job definitions
  #
  # @param job_definitions [Hash] Job definitions from YamlProcessor (job_name => config)
  # @return [Array<MockJob>] Array of MockJob instances
  def build_mock_jobs(job_definitions)
    job_counter = 0

    job_definitions.map do |job_name, job_def|
      job_counter += 1

      # Extract job needs (dependencies)
      needs = extract_job_needs(job_def)

      # Extract tags
      tags = job_def[:tags] || job_def['tags'] || []

      MockJob.new(
        id: job_counter,
        name: job_name.to_s,
        stage: (job_def[:stage] || job_def['stage']).to_s,
        script: job_def[:script] || job_def['script'] || [],
        image: job_def[:image] || job_def['image'],
        services: job_def[:services] || job_def['services'] || [],
        artifacts: job_def[:artifacts] || job_def['artifacts'],
        variables: job_def[:variables] || job_def['variables'] || {},
        tags: tags,
        needs: needs
      )
    end
  end

  # Extract job needs from job definition
  # Handles both simple array format and complex needs format
  #
  # @param job_def [Hash] Job definition
  # @return [Array<String>] Job names this job depends on
  def extract_job_needs(job_def)
    needs = job_def[:needs] || job_def['needs']
    return [] if needs.nil? || needs.empty?

    # Handle complex needs format: { job: [...] }
    if needs.is_a?(Hash)
      job_needs = needs[:job] || needs['job'] || []
      return job_needs.map { |need| need[:name] || need['name'] }.compact
    end

    # Handle simple array format
    if needs.is_a?(Array)
      return needs.map do |need|
        if need.is_a?(Hash)
          need[:name] || need['name']
        else
          need.to_s
        end
      end.compact
    end

    []
  end

  # Validate that all job needs reference existing jobs
  # Fail-fast principle: catch configuration errors early
  #
  # @raise [ArgumentError] if a job references a non-existent dependency
  def validate_job_needs
    job_names = @jobs.map(&:name)

    @jobs.each do |job|
      job.needs.each do |needed_job|
        unless job_names.include?(needed_job)
          raise ArgumentError, "Job '#{job.name}' has invalid need '#{needed_job}': job does not exist"
        end
      end
    end
  end

  # Check if all dependencies for a job are satisfied
  # Looks at both stage order and explicit needs
  #
  # @param job [MockJob] Job to check
  # @return [Boolean] True if dependencies are satisfied
  def dependencies_satisfied?(job)
    # Check explicit needs (DAG dependencies)
    # If job has explicit needs, only check those (ignore stage order)
    if job.needs.any?
      return job.needs.all? do |needed_job_name|
        needed_job = find_job(needed_job_name)
        needed_job && needed_job.completed?
      end
    end

    # No explicit needs: check stage-based dependencies
    # All jobs in prior stages must be complete
    job_stage_index = @stages.index(job.stage)

    # First stage: no dependencies
    return true if job_stage_index.nil? || job_stage_index.zero?

    # Check all jobs in prior stages are complete
    prior_stages = @stages[0...job_stage_index]
    prior_jobs = @jobs.select { |j| prior_stages.include?(j.stage) }
    prior_jobs.all?(&:completed?)
  end
end
