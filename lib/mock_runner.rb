# frozen_string_literal: true

# MockRunner simulates a GitLab Runner client that can accept and execute jobs
# It tracks capacity, tags, and handles job lifecycle events
class MockRunner
  attr_reader :id, :tags, :executor, :max_jobs, :running_jobs

  # Initialize a mock runner from runner data
  #
  # @param runner_data [Hash] Runner configuration hash (parsed from JSON)
  def initialize(runner_data)
    @id = runner_data['id'] || runner_data[:id]
    # Support both 'tags' and 'tag_list' field names (GitLab API compatibility)
    @tags = runner_data['tags'] || runner_data[:tags] ||
            runner_data['tag_list'] || runner_data[:tag_list] || []
    @executor = runner_data['executor'] || runner_data[:executor] || 'shell'
    # Support both 'max_jobs' and 'concurrent' field names
    @max_jobs = runner_data['max_jobs'] || runner_data[:max_jobs] ||
                runner_data['concurrent'] || runner_data[:concurrent] || 1
    @running_jobs = 0
    @jobs = []

    # Extended configuration
    @run_untagged = runner_data['run_untagged'] || runner_data[:run_untagged] || false
    @locked = runner_data['locked'] || runner_data[:locked] || false
    @access_level = runner_data['access_level'] || runner_data[:access_level] || 'not_protected'
  end

  # Check if this runner can handle the given job based on tags
  #
  # @param job [MockJob] Job to check compatibility with
  # @return [Boolean] True if runner can handle the job
  def can_handle?(job)
    raise ArgumentError, "job cannot be nil" if job.nil?

    job_tags = job.tag_list || []

    # Job has no tags: runner must accept untagged jobs
    if job_tags.empty?
      return @run_untagged
    end

    # Job has tags: all job tags must be present in runner tags
    # (job tags must be a subset of runner tags)
    job_tags.all? { |tag| @tags.include?(tag) }
  end

  # Check if this runner has capacity to accept another job
  #
  # @return [Boolean] True if runner can accept more jobs
  def has_capacity?
    @running_jobs < @max_jobs
  end

  # Assign a job to this runner
  #
  # @param job [MockJob] Job to assign
  # @return [Boolean] True if assignment successful
  def assign_job(job)
    raise ArgumentError, "job cannot be nil" if job.nil?

    @running_jobs += 1
    @jobs << job

    # TODO: Emit job_assigned event when event system is implemented

    true
  end

  # Release a job from this runner (when completed or failed)
  #
  # @param job [MockJob] Job to release
  # @return [Boolean] True if release successful
  def release_job(job)
    raise ArgumentError, "job cannot be nil" if job.nil?

    # Remove job from tracked jobs
    @jobs.delete(job)

    # Decrement counter, but never go below 0
    # This prevents underflow if release_job is called multiple times
    @running_jobs = [@running_jobs - 1, 0].max

    true
  end

  # Handle a job assignment and log job details
  #
  # @param job_payload [Hash] Job payload from server
  # @return [Symbol] Job execution result (:success, :failure)
  def handle_job_assignment(job_payload)
    # TODO: Extract job payload data
    # TODO: Log runner ID and job ID
    # TODO: Log project name
    # TODO: Log stage name
    # TODO: Log job name
    # TODO: Log script commands
    # TODO: Log Docker image if present
    # TODO: Log services if present
    # TODO: Log artifacts if present
    # TODO: Emit job_started event
    # TODO: Simulate job execution
    # TODO: Emit job_completed event with success status
    # TODO: Return execution result
    raise NotImplementedError, "handle_job_assignment not yet implemented"
  end
end
