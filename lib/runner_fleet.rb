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

require 'json'

# RunnerFleet manages a collection of mock runners and handles
# runner discovery, availability checking, and job assignment
class RunnerFleet
  attr_reader :runners

  # Initialize an empty runner fleet
  def initialize
    @runners = []
  end

  # Load runner configurations from a directory
  #
  # @param directory [String] Path to directory containing runner JSON files
  # @return [Integer] Number of runners loaded
  # @raise [ArgumentError] if directory does not exist or is not a directory
  def load_runners(directory)
    # Fail-fast: Validate directory exists and is actually a directory
    unless Dir.exist?(directory)
      raise ArgumentError, "directory does not exist: #{directory}"
    end

    unless File.directory?(directory)
      raise ArgumentError, "not a directory: #{directory}"
    end

    # Find all JSON files in the directory
    json_files = Dir.glob(File.join(directory, "*.json"))

    loaded_count = 0

    json_files.each do |file_path|
      begin
        # Read and parse JSON file
        content = File.read(file_path)
        runner_data = JSON.parse(content)

        # Validate required fields before creating runner
        validate_runner_data(runner_data, file_path)

        # Create MockRunner instance and add to fleet
        runner = MockRunner.new(runner_data)
        @runners << runner
        loaded_count += 1
      rescue JSON::ParserError => e
        raise ArgumentError, "Failed to parse JSON in runner file '#{file_path}': #{e.message}"
      rescue Errno::ENOENT => e
        raise ArgumentError, "Failed to read runner file '#{file_path}': #{e.message}"
      rescue ArgumentError => e
        # Re-raise ArgumentError with file context if not already included
        if e.message.include?(file_path)
          raise
        else
          raise ArgumentError, "Error in runner file '#{file_path}': #{e.message}"
        end
      rescue StandardError => e
        raise ArgumentError, "Unexpected error loading runner file '#{file_path}': #{e.message}"
      end
    end

    loaded_count
  end

  # Find an available runner that can handle the given job
  #
  # @param job [MockJob] Job to find a runner for
  # @return [MockRunner, nil] Available runner or nil if none available
  # @raise [ArgumentError] if job is nil
  def find_available_runner(job)
    # Fail-fast: Validate input
    raise ArgumentError, "job cannot be nil" if job.nil?

    # Iterate through runners and return first match
    # Pure function: no side effects, order-dependent but deterministic
    @runners.each do |runner|
      # Check both tag compatibility and capacity
      # Order matters: tag check is cheaper than capacity check
      if runner.can_handle?(job) && runner.has_capacity?
        return runner
      end
    end

    # Explicit: Return nil when no runner available
    nil
  end

  # Runners that could ever take the job: their tags match (load_runners
  # rejects max_jobs < 1, so each has capacity once idle). Empty means the
  # job can never start on this fleet, however long it waits; vs.
  # find_available_runner nil, which may only mean busy right now.
  #
  # @param job [MockJob]
  # @return [Array<MockRunner>]
  def eligible_runners(job)
    raise ArgumentError, "job cannot be nil" if job.nil?

    @runners.select { |runner| runner.can_handle?(job) }
  end

  private

  # Validate runner data has all required fields
  #
  # @param runner_data [Hash] Parsed JSON data
  # @param file_path [String] File path for error messages
  # @raise [ArgumentError] if required fields are missing or invalid
  def validate_runner_data(runner_data, file_path)
    # Validate ID field (required)
    unless runner_data.key?('id')
      raise ArgumentError, "Runner file '#{file_path}': missing required field 'id'"
    end

    unless runner_data['id'].is_a?(String) || runner_data['id'].is_a?(Integer)
      raise ArgumentError, "Runner file '#{file_path}': field 'id' must be a string or integer, got #{runner_data['id'].class}"
    end

    # Validate tags field (required, accept both 'tags' and 'tag_list')
    tags = runner_data['tags'] || runner_data['tag_list']
    unless tags
      raise ArgumentError, "Runner file '#{file_path}': missing required field 'tags' (or 'tag_list')"
    end

    unless tags.is_a?(Array)
      raise ArgumentError, "Runner file '#{file_path}': field 'tags' (or 'tag_list') must be an array, got #{tags.class}"
    end

    # Validate executor field (required)
    unless runner_data.key?('executor')
      raise ArgumentError, "Runner file '#{file_path}': missing required field 'executor'"
    end

    unless runner_data['executor'].is_a?(String)
      raise ArgumentError, "Runner file '#{file_path}': field 'executor' must be a string, got #{runner_data['executor'].class}"
    end

    # Validate max_jobs field (required, accept both 'max_jobs' and 'concurrent')
    max_jobs = runner_data['max_jobs'] || runner_data['concurrent']
    unless max_jobs
      raise ArgumentError, "Runner file '#{file_path}': missing required field 'max_jobs' (or 'concurrent')"
    end

    unless max_jobs.is_a?(Integer) && max_jobs >= 1
      raise ArgumentError, "Runner file '#{file_path}': field 'max_jobs' (or 'concurrent') must be a positive integer, got #{max_jobs.inspect}"
    end

    # All validations passed
    true
  end
end
