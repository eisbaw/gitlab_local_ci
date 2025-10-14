# frozen_string_literal: true

# MockJob represents a CI/CD job with state management
# It tracks job metadata and handles state transitions
class MockJob
  attr_reader :id, :name, :stage, :script, :image, :services, :artifacts,
              :variables, :tag_list, :status, :needs

  # Job status states
  STATUS_PENDING = :pending
  STATUS_RUNNING = :running
  STATUS_COMPLETED = :completed
  STATUS_FAILED = :failed
  STATUS_CANCELED = :canceled
  STATUS_SKIPPED = :skipped

  # Initialize a mock job from job data
  # Supports both keyword arguments and hash parameter for flexibility
  #
  # @param id [Integer] Job ID
  # @param name [String] Job name
  # @param stage [String] Stage name
  # @param script [Array<String>] Script commands
  # @param image [String, nil] Docker image
  # @param services [Array, nil] Docker services
  # @param artifacts [Hash, nil] Artifact configuration
  # @param variables [Hash] Job variables
  # @param tags [Array<String>] Runner tags
  # @param needs [Array<String>] Job dependencies
  def initialize(id:, name:, stage:, script:, image: nil, services: [], artifacts: nil, variables: {}, tags: [], needs: [])
    @id = id
    @name = name
    @stage = stage
    @script = script
    @image = image
    @services = services
    @artifacts = artifacts
    @variables = variables
    @tag_list = tags
    @needs = needs
    @status = STATUS_PENDING

    # TODO: Parse additional job configuration
    # TODO: Handle when/rules conditions
    # TODO: Handle allow_failure flag
    # TODO: Handle retry configuration
  end

  # Transition job to a new status
  #
  # @param new_status [Symbol] New status to transition to
  # @return [Boolean] True if transition successful
  def transition_to(new_status)
    # Fail-fast: Validate input
    valid_statuses = [
      STATUS_PENDING,
      STATUS_RUNNING,
      STATUS_COMPLETED,
      STATUS_FAILED,
      STATUS_CANCELED,
      STATUS_SKIPPED
    ]

    unless valid_statuses.include?(new_status)
      raise ArgumentError, "Invalid status: #{new_status}. Must be one of: #{valid_statuses.join(', ')}"
    end

    # Validate state transition is valid
    # Valid transitions:
    # pending -> running, canceled, skipped
    # running -> completed, failed, canceled
    # Other transitions are invalid (can't restart completed jobs, etc.)
    case @status
    when STATUS_PENDING
      unless [STATUS_RUNNING, STATUS_CANCELED, STATUS_SKIPPED].include?(new_status)
        raise ArgumentError, "Cannot transition from pending to #{new_status}"
      end
    when STATUS_RUNNING
      unless [STATUS_COMPLETED, STATUS_FAILED, STATUS_CANCELED].include?(new_status)
        raise ArgumentError, "Cannot transition from running to #{new_status}"
      end
    when STATUS_COMPLETED, STATUS_FAILED, STATUS_CANCELED, STATUS_SKIPPED
      # Terminal states - no transitions allowed
      raise ArgumentError, "Cannot transition from terminal state #{@status} to #{new_status}"
    end

    # Update status
    @status = new_status

    # TODO: Emit state change event when event system is implemented

    true
  end

  # Check if job is in pending state
  #
  # @return [Boolean] True if job is pending
  def pending?
    @status == STATUS_PENDING
  end

  # Check if job is in running state
  #
  # @return [Boolean] True if job is running
  def running?
    @status == STATUS_RUNNING
  end

  # Check if job is in completed state
  #
  # @return [Boolean] True if job is completed
  def completed?
    @status == STATUS_COMPLETED
  end

  # Check if job is in failed state
  #
  # @return [Boolean] True if job failed
  def failed?
    @status == STATUS_FAILED
  end

  # Check if job is in canceled state
  #
  # @return [Boolean] True if job was canceled
  def canceled?
    @status == STATUS_CANCELED
  end

  # Check if job is in skipped state
  #
  # @return [Boolean] True if job was skipped
  def skipped?
    @status == STATUS_SKIPPED
  end

  # Check if job is in a finished state
  #
  # @return [Boolean] True if job is completed, failed, canceled, or skipped
  def finished?
    completed? || failed? || canceled? || skipped?
  end
end
