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
  # @param data [Hash] Job data with string or symbol keys
  def initialize(data)
    # Handle both string and symbol keys
    @id = data['id'] || data[:id]
    @name = data['name'] || data[:name]
    @stage = data['stage'] || data[:stage]
    @script = data['script'] || data[:script] || []
    @image = data['image'] || data[:image]
    @services = data['services'] || data[:services] || []
    @artifacts = data['artifacts'] || data[:artifacts]
    @variables = data['variables'] || data[:variables] || {}

    # Handle both 'tags' and 'tag_list' keys
    @tag_list = data['tag_list'] || data[:tag_list] || data['tags'] || data[:tags] || []

    @needs = data['needs'] || data[:needs] || []
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
    # Validate input
    valid_statuses = [
      STATUS_PENDING,
      STATUS_RUNNING,
      STATUS_COMPLETED,
      STATUS_FAILED,
      STATUS_CANCELED,
      STATUS_SKIPPED
    ]

    unless valid_statuses.include?(new_status)
      raise ArgumentError, "unknown status: #{new_status}. Must be one of: #{valid_statuses.join(', ')}"
    end

    # Handle same-state transition as no-op
    return true if @status == new_status

    # Validate state transition is valid
    # Valid transitions:
    # pending -> running, canceled, skipped
    # running -> completed, failed, canceled
    # Terminal states (completed, failed, canceled, skipped) cannot transition
    case @status
    when STATUS_PENDING
      unless [STATUS_RUNNING, STATUS_CANCELED, STATUS_SKIPPED].include?(new_status)
        raise ArgumentError, "invalid transition from pending to #{new_status}"
      end
    when STATUS_RUNNING
      unless [STATUS_COMPLETED, STATUS_FAILED, STATUS_CANCELED].include?(new_status)
        raise ArgumentError, "invalid transition from running to #{new_status}"
      end
    when STATUS_COMPLETED, STATUS_FAILED, STATUS_CANCELED, STATUS_SKIPPED
      # Terminal states - no transitions allowed
      raise ArgumentError, "invalid transition from terminal state #{@status} to #{new_status}"
    end

    # Update status
    @status = new_status
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
