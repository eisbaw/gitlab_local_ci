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

require 'set'
require_relative 'mock_job'
require_relative 'pipeline_builder'

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

  # Upstream Entry::Job default stage.
  DEFAULT_JOB_STAGE = PipelineBuilder::DEFAULT_JOB_STAGE

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
    @previous_status = nil # Track previous status for change detection

    # Convert job hash to MockJob instances
    @jobs = build_mock_jobs(jobs)

    # Validate job dependencies
    validate_job_needs

    # Who waits for whom is fixed at creation; only job states change. Kept
    # so each simulated tick is O(jobs x previous jobs), not a re-scan of
    # stages and names per job.
    @previous_jobs = @jobs.to_h { |job| [job.name, select_previous_jobs(job)] }.freeze
  end

  # Pipeline status, derived from job states (never stored): the composite
  # of all jobs once they are finished (upstream status_of_all), else
  # pending until the first job starts, running after.
  #
  # @return [Symbol] STATE_* or :skipped / :canceled
  def status
    finished = composite_status(@jobs, dag: false)
    return finished if finished
    return STATE_PENDING if @jobs.all?(&:pending?)

    STATE_RUNNING
  end

  # Check if status has changed since last check
  # Updates internal tracking after checking
  #
  # @return [Hash, nil] Hash with :old and :new status if changed, nil otherwise
  def status_changed?
    current = status
    previous = @previous_status || STATE_PENDING

    if current != previous
      @previous_status = current
      { old: previous, new: current }
    else
      nil
    end
  end

  # Check if pipeline has pending jobs
  #
  # @return [Boolean] True if any jobs are pending
  def has_pending_jobs?
    @jobs.any?(&:pending?)
  end

  # Pending jobs that may start now: their previous jobs are finished and
  # their when: accepts the result. Pure query; see skip_blocked_jobs.
  #
  # @return [Array<MockJob>] in config order
  def pending_jobs
    @jobs.select do |job|
      next false unless job.pending?

      previous = previous_status(job)
      previous && runnable_after?(job, previous)
    end
  end

  # Skip every pending job whose previous jobs are finished with a result
  # its when: rejects (upstream ProcessBuildService: processable.skip).
  # A skip can decide the jobs after it, so repeat to a fixed point; each
  # pass skips at least one job or stops, so at most jobs.size + 1 passes.
  #
  # @return [Array<MockJob>] jobs skipped by this call, in skip order
  def skip_blocked_jobs
    skipped = []
    (@jobs.size + 1).times do
      blocked = @jobs.select do |job|
        next false unless job.pending?

        previous = previous_status(job)
        previous && !runnable_after?(job, previous)
      end
      return skipped if blocked.empty?

      blocked.each { |job| job.transition_to(MockJob::STATUS_SKIPPED) }
      skipped.concat(blocked)
    end
    raise "skip_blocked_jobs: no fixed point after #{@jobs.size + 1} passes"
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

  # Result of the jobs this one waits for, or nil while any is unfinished
  # (upstream AtomicProcessingService#status_of_previous_jobs).
  #
  # @param job [MockJob]
  # @return [Symbol, nil]
  def previous_status(job)
    composite_status(previous_jobs(job), dag: job.dag?)
  end

  # The jobs `job` waits for: its needs for a DAG job, every job of every
  # earlier stage otherwise.
  #
  # @param job [MockJob]
  # @return [Array<MockJob>]
  def previous_jobs(job)
    @previous_jobs.fetch(job.name)
  end

  private

  # Build MockJob instances from GitLab job definitions
  #
  # @param job_definitions [Hash] job name => config (PipelineBuilder::Result#pipeline_jobs)
  # @return [Array<MockJob>] Array of MockJob instances
  def build_mock_jobs(job_definitions)
    job_names = job_definitions.keys.map(&:to_s)

    job_definitions.each_with_index.map do |(job_name, job_def), index|
      needs_config = job_def['needs'] || job_def[:needs]
      stage = (job_def['stage'] || job_def[:stage] || DEFAULT_JOB_STAGE).to_s
      unless @stages.include?(stage)
        raise ArgumentError, "Job '#{job_name}' has stage '#{stage}', not in stages #{@stages.inspect}"
      end

      MockJob.new(
        id: index + 1,
        name: job_name.to_s,
        stage: stage,
        script: job_def[:script] || job_def['script'] || [],
        image: job_def[:image] || job_def['image'],
        services: job_def[:services] || job_def['services'] || [],
        artifacts: job_def[:artifacts] || job_def['artifacts'],
        variables: job_def[:variables] || job_def['variables'] || {},
        tags: job_def[:tags] || job_def['tags'] || [],
        needs: extract_job_needs(needs_config, job_names),
        scheduling_type: needs_config.nil? ? :stage : :dag,
        allow_failure: job_def['allow_failure'] || job_def[:allow_failure],
        when: job_def['when'] || job_def[:when]
      )
    end
  end

  # Names of the jobs in this pipeline that `needs:` waits for (upstream
  # aggregated_needs_names): `job:` of the map form, an optional need on a
  # job not in the pipeline dropped, cross-pipeline needs ignored. A
  # required need on a missing job stays and fails validate_job_needs.
  #
  # @param needs_config [Array, nil] the job's `needs:`
  # @param job_names [Array<String>] jobs in this pipeline
  # @return [Array<String>]
  def extract_job_needs(needs_config, job_names)
    PipelineBuilder.same_pipeline_needs(needs_config).filter_map do |name, optional|
      name.to_s unless optional && !job_names.include?(name.to_s)
    end
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

  # previous_jobs, computed once at creation.
  def select_previous_jobs(job)
    return @jobs.select { |j| job.needs.include?(j.name) } if job.dag?

    stage_index = @stages.index(job.stage)
    @jobs.select { |j| @stages.index(j.stage) < stage_index }
  end

  # Upstream Ci::ProcessBuildService#valid_statuses_for_processable. manual
  # and delayed jobs run like on_success: the simulator has no one to
  # press play and does not wait.
  #
  # @param job [MockJob]
  # @param previous [Symbol] previous_status(job), not nil
  def runnable_after?(job, previous)
    case job.when_to_run
    when 'on_success', 'manual', 'delayed'
      job.dag? ? previous == :success : %i[success skipped].include?(previous)
    when 'on_failure' then previous == :failed
    when 'always' then %i[success failed skipped].include?(previous)
    else raise ArgumentError, "job '#{job.name}': unhandled when: '#{job.when_to_run}'"
    end
  end

  # Gitlab::Ci::Status::Composite for the statuses the simulator produces;
  # nil while any job is unfinished. No jobs is success (upstream
  # status_for_array), which is what lets `needs: []` and the first stage
  # start at once. A failed or canceled job with allow_failure counts as
  # success (success_with_warnings).
  #
  # @param jobs [Array<MockJob>]
  # @param dag [Boolean] a skipped need skips the DAG job
  # @return [Symbol, nil] :success, :failed, :skipped, :canceled or nil
  def composite_status(jobs, dag:)
    return :success if jobs.empty?
    return nil unless jobs.all?(&:finished?)

    statuses = jobs.map do |job|
      next :success if job.completed?
      next :success if job.allow_failure && (job.failed? || job.canceled?)

      job.status
    end.to_set

    return :skipped if dag && statuses.include?(:skipped)
    return :skipped if statuses == Set[:skipped]
    return :success if statuses.subset?(Set[:success, :skipped])
    return :canceled if statuses.subset?(Set[:canceled, :success, :skipped])

    :failed
  end
end
