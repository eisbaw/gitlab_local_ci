# frozen_string_literal: true

require 'gitlab'
require 'json'
require 'fileutils'

# RunnerExporter exports runner configurations from a GitLab instance
# to JSON files that can be used by the mock runner fleet
#
# This tool fetches runner information via GitLab API and writes
# individual JSON files for each runner in the specified output directory
class RunnerExporter
  # Custom error for API-related failures
  class APIError < StandardError; end

  # Custom error for network-related failures
  class NetworkError < StandardError; end

  # Custom error for authentication failures
  class AuthenticationError < StandardError; end

  # Initialize the runner exporter
  def initialize
    @client = nil
  end

  # Export runner configurations from a GitLab instance to JSON files
  #
  # @param gitlab_url [String] GitLab instance URL (e.g., 'https://gitlab.com')
  # @param token [String] GitLab API private token with 'read_api' scope
  # @param output_dir [String] Directory to write runner JSON files (default: './runners')
  # @return [Integer] Number of runners exported
  #
  # @raise [AuthenticationError] If token is invalid or lacks permissions
  # @raise [NetworkError] If network connection fails
  # @raise [APIError] If GitLab API returns an error
  #
  # @example Export runners from GitLab.com
  #   exporter = RunnerExporter.new
  #   count = exporter.export_from_gitlab(
  #     'https://gitlab.com',
  #     'your-api-token',
  #     './runners'
  #   )
  #   puts "Exported #{count} runners"
  def export_from_gitlab(gitlab_url, token, output_dir = './runners')
    # Validate inputs
    raise ArgumentError, "gitlab_url cannot be nil or empty" if gitlab_url.nil? || gitlab_url.empty?
    raise ArgumentError, "token cannot be nil or empty" if token.nil? || token.empty?

    # Initialize GitLab API client
    initialize_client(gitlab_url, token)

    # Ensure output directory exists
    FileUtils.mkdir_p(output_dir)

    puts "Connecting to GitLab instance: #{gitlab_url}"

    # Fetch all runners from GitLab instance
    runners = fetch_all_runners

    if runners.empty?
      puts "No runners found on the GitLab instance"
      return 0
    end

    puts "Found #{runners.count} runner(s), exporting to #{output_dir}/"

    # Export each runner to a JSON file
    exported_count = 0
    runners.each do |runner|
      export_runner(runner, output_dir)
      exported_count += 1
    end

    puts "Successfully exported #{exported_count} runner(s)"
    exported_count
  rescue ArgumentError
    # Re-raise validation errors directly (fail-fast)
    raise
  rescue Gitlab::Error::Unauthorized => e
    raise AuthenticationError, "Authentication failed: #{e.message}. Check your API token."
  rescue Gitlab::Error::Forbidden => e
    raise AuthenticationError, "Access forbidden: #{e.message}. Token may lack 'read_api' scope."
  rescue Gitlab::Error::MissingCredentials => e
    raise AuthenticationError, "Missing credentials: #{e.message}"
  rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    raise NetworkError, "Network error: #{e.message}. Check GitLab URL and connectivity."
  rescue Gitlab::Error::Error => e
    raise APIError, "GitLab API error: #{e.message}"
  rescue StandardError => e
    raise APIError, "Unexpected error: #{e.class} - #{e.message}"
  end

  private

  # Initialize the GitLab API client
  #
  # @param gitlab_url [String] GitLab instance URL
  # @param token [String] GitLab API private token
  def initialize_client(gitlab_url, token)
    # TODO: Configure GitLab client with custom options
    # TODO: Set user agent for better API tracking
    # TODO: Configure timeout settings
    @client = Gitlab.client(
      endpoint: gitlab_url,
      private_token: token
    )
  end

  # Fetch all runners from the GitLab instance with pagination
  #
  # @return [Array] Array of runner objects from GitLab API
  def fetch_all_runners
    # TODO: Implement pagination handling for large runner fleets
    # TODO: Add filtering options (active only, specific tags, etc.)
    # TODO: Add progress output for large datasets

    puts "Fetching runners from GitLab API..."

    # Fetch runners with pagination (GitLab API supports per_page parameter)
    # The gitlab gem handles pagination automatically with auto_paginate
    runners = []
    page = 1
    per_page = 100

    loop do
      # Fetch a page of runners
      page_runners = @client.runners(page: page, per_page: per_page)

      break if page_runners.empty?

      runners.concat(page_runners)
      puts "  Fetched page #{page} (#{page_runners.count} runner(s))"

      # Break if we got fewer results than per_page (last page)
      break if page_runners.count < per_page

      page += 1
    end

    runners
  end

  # Export a single runner to a JSON file
  #
  # @param runner [Gitlab::ObjectifiedHash] Runner object from GitLab API
  # @param output_dir [String] Directory to write the JSON file
  def export_runner(runner, output_dir)
    # TODO: Transform runner data to match mock runner format
    # TODO: Add additional metadata (export timestamp, source URL)
    # TODO: Handle optional fields gracefully

    runner_id = runner.id
    filename = File.join(output_dir, "runner_#{runner_id}.json")

    # Convert runner to hash and format as JSON
    runner_data = format_runner_data(runner)
    json_content = JSON.pretty_generate(runner_data)

    # Write to file
    File.write(filename, json_content)

    puts "  ✓ Exported runner '#{runner.description || runner_id}' to #{filename}"
  rescue StandardError => e
    warn "  ✗ Failed to export runner #{runner_id}: #{e.message}"
  end

  # Format runner data from GitLab API to our JSON schema
  #
  # @param runner [Gitlab::ObjectifiedHash] Runner object from GitLab API
  # @return [Hash] Formatted runner data
  def format_runner_data(runner)
    # TODO: Map GitLab runner fields to our schema
    # TODO: Handle differences between GitLab versions
    # TODO: Provide sensible defaults for missing fields

    # Build runner hash matching our schema
    data = {
      'id' => "runner_#{runner.id}",
      'description' => runner.description || "Runner #{runner.id}",
      'active' => runner.active || runner.is_shared || false,
      'tags' => runner.tag_list || [],
      'run_untagged' => runner.run_untagged || false,
      'locked' => runner.locked || false,
      'executor' => determine_executor(runner),
      'max_jobs' => 1 # Default, as GitLab API doesn't expose this directly
    }

    # Add optional fields if available
    if runner.respond_to?(:access_level)
      data['access_level'] = runner.access_level
    end

    if runner.respond_to?(:maximum_timeout)
      data['maximum_timeout'] = runner.maximum_timeout
    end

    # Add status information
    if runner.respond_to?(:status)
      data['status'] = runner.status
    end

    # Add architecture/platform info if available
    if runner.respond_to?(:architecture)
      data['architecture'] = runner.architecture
    end

    if runner.respond_to?(:platform)
      data['platform'] = runner.platform
    end

    data
  end

  # Determine the executor type from runner information
  #
  # @param runner [Gitlab::ObjectifiedHash] Runner object from GitLab API
  # @return [String] Executor type (shell, docker, etc.)
  def determine_executor(runner)
    # TODO: Improve executor detection logic
    # GitLab API doesn't directly expose executor type
    # We make educated guesses based on available information

    # Check if runner has specific tags indicating executor type
    tags = runner.tag_list || []
    return 'docker' if tags.include?('docker')
    return 'kubernetes' if tags.include?('kubernetes') || tags.include?('k8s')
    return 'shell' if tags.include?('shell')

    # Default to shell executor
    'shell'
  end
end
