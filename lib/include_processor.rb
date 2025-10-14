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
require 'net/http'
require 'uri'
require 'set'

# Custom exception raised when include depth limit is exceeded
class IncludeDepthExceededError < StandardError
  attr_reader :depth, :max_depth

  def initialize(depth, max_depth)
    @depth = depth
    @max_depth = max_depth
    super("Include depth exceeded: #{depth} > #{max_depth}")
  end
end

# Processes 'include' directives in GitLab CI configuration
# Supports all GitLab include types with depth limiting
class IncludeProcessor
  # All supported include types
  INCLUDE_TYPES = %i[
    local
    file
    remote
    template
    project
    component
  ].freeze

  # Maximum include depth (matches GitLab's limit)
  MAX_DEPTH = 150

  attr_reader :project_path, :gitlab_templates_path

  # Initialize the include processor
  #
  # @param project_path [String] Path to the project root
  # @param gitlab_templates_path [String] Path to GitLab templates directory
  def initialize(project_path:, gitlab_templates_path: nil)
    @project_path = project_path
    @gitlab_templates_path = gitlab_templates_path
    @processed_includes = Set.new # Track processed includes to detect circular refs
  end

  # Process all includes in a configuration
  #
  # @param config [Hash] The GitLab CI configuration
  # @param depth [Integer] Current include depth
  # @return [Hash] Merged configuration with all includes resolved
  def process_includes(config, depth = 0)
    # Fail-fast: Check depth limit
    raise IncludeDepthExceededError.new(depth, MAX_DEPTH) if depth > MAX_DEPTH

    # Extract include directive
    includes = config['include']
    return config unless includes

    # Normalize to array
    includes = [includes] unless includes.is_a?(Array)

    # Start with base config (without include key)
    result = config.dup
    result.delete('include')

    # Process each include
    includes.each do |include_spec|
      # Determine include type and fetch content
      include_type = determine_include_type(include_spec)

      # Generate identifier for circular detection
      identifier = include_identifier(include_spec)

      if @processed_includes.include?(identifier)
        raise StandardError, "Circular include detected: #{identifier}"
      end

      @processed_includes.add(identifier)

      # Fetch content based on type
      content = case include_type
                when :local
                  fetch_local_include(include_spec)
                when :remote
                  fetch_remote_include(include_spec)
                when :template
                  fetch_template_include(include_spec)
                when :project, :file
                  fetch_project_include(include_spec)
                when :component
                  fetch_component_include(include_spec)
                else
                  raise "Unknown include type: #{include_type}"
                end

      # Parse YAML content
      included_config = YAML.safe_load(content, permitted_classes: [Symbol], aliases: true)

      # Recursively process includes in the included file
      included_config = process_includes(included_config, depth + 1)

      # Deep merge into result
      result = deep_merge(result, included_config)

      @processed_includes.delete(identifier)
    end

    result
  end

  private

  # Determine the type of include from the spec
  #
  # @param include_spec [Hash, String] Include specification
  # @return [Symbol] Include type
  def determine_include_type(include_spec)
    return :local if include_spec.is_a?(String)

    return :local if include_spec.key?('local')
    return :remote if include_spec.key?('remote')
    return :template if include_spec.key?('template')
    return :component if include_spec.key?('component')
    return :project if include_spec.key?('project')
    return :file if include_spec.key?('file')

    raise "Unable to determine include type from spec: #{include_spec.inspect}"
  end

  # Fetch a local include file
  #
  # @param include_spec [Hash, String] Include specification
  # @return [String] File contents
  def fetch_local_include(include_spec)
    # Extract file path
    file_path = include_spec.is_a?(String) ? include_spec : include_spec['local']

    # Security: Validate path doesn't contain traversal sequences or absolute paths
    if file_path.include?('..') || file_path.start_with?('/')
      raise "Invalid local include path: #{file_path}. Path must be relative and cannot contain '..'"
    end

    # Resolve to absolute path and validate it's within project
    full_path = File.expand_path(File.join(@project_path, file_path))
    project_path_abs = File.expand_path(@project_path)

    # Fail-fast: Ensure path doesn't escape project directory
    unless full_path.start_with?(project_path_abs + File::SEPARATOR) || full_path == project_path_abs
      raise "Local include path escapes project directory: #{file_path}"
    end

    # Security: Check for symlink attacks
    if File.symlink?(full_path)
      real_path = File.realpath(full_path)
      unless real_path.start_with?(project_path_abs + File::SEPARATOR)
        raise "Local include symlink target escapes project directory: #{file_path}"
      end
    end

    # Fail-fast: Check if file exists
    unless File.exist?(full_path)
      raise "Local include file not found: #{file_path}"
    end

    File.read(full_path)
  end

  # Fetch a file include from another project
  #
  # @param include_spec [Hash] Include specification with 'project' and 'file' keys
  # @return [String] File contents
  def fetch_file_include(include_spec)
    # This is an alias for fetch_project_include
    fetch_project_include(include_spec)
  end

  # Fetch a remote include via HTTP(S)
  #
  # @param include_spec [Hash] Include specification with 'remote' key
  # @return [String] File contents
  def fetch_remote_include(include_spec)
    url_string = include_spec['remote']

    # Validate and parse URL
    uri = validate_remote_url(url_string)

    # Fetch with timeouts to prevent resource exhaustion
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: true,
      read_timeout: 5,      # 5 second read timeout
      open_timeout: 3,      # 3 second connection timeout
      verify_mode: OpenSSL::SSL::VERIFY_PEER  # Verify SSL certificates
    ) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      http.request(request)
    end

    # Fail-fast: Check response status
    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to fetch remote include #{url_string}: HTTP #{response.code} #{response.message}"
    end

    response.body
  rescue StandardError => e
    raise "Error fetching remote include #{url_string}: #{e.message}"
  end

  # Validate a remote URL for security
  #
  # @param url_string [String] URL to validate
  # @return [URI] Parsed and validated URI
  # @raise [RuntimeError] If URL is invalid or not allowed
  def validate_remote_url(url_string)
    uri = URI.parse(url_string)

    # Fail-fast: Validate HTTPS only (security best practice)
    unless uri.scheme == 'https'
      raise "Remote includes must use HTTPS for security: #{url_string}"
    end

    # Fail-fast: Validate host is present
    unless uri.host
      raise "Remote URL missing host: #{url_string}"
    end

    # SSRF Protection: Block requests to private IP ranges
    # This prevents attacks targeting internal services
    # Note: DNS rebinding attacks are still possible (hostname could resolve to
    # private IP after this check). Ruby's Net::HTTP doesn't provide hooks to
    # validate resolved IPs. This is a known limitation.
    validate_not_private_ip(uri.host)

    # Optional: Check against allowlist if configured
    # Set GITLAB_CI_ALLOWED_DOMAINS environment variable to enable
    allowed_domains = ENV['GITLAB_CI_ALLOWED_DOMAINS']
    if allowed_domains && !allowed_domains.empty?
      domains = allowed_domains.split(',').map(&:strip)
      unless domains.include?(uri.host)
        raise "Remote host not in allowlist: #{uri.host}. " \
              "Allowed domains: #{domains.join(', ')}"
      end
    end

    uri
  rescue URI::InvalidURIError => e
    raise "Invalid remote URL: #{url_string} - #{e.message}"
  end

  # Validate that a hostname does not resolve to a private IP address
  # Prevents SSRF attacks targeting internal services
  #
  # @param hostname [String] Hostname to validate
  # @raise [RuntimeError] If hostname resolves to private IP
  def validate_not_private_ip(hostname)
    require 'resolv'

    begin
      # Resolve hostname to IP address
      ip = Resolv.getaddress(hostname)

      # Check for private IP ranges (SSRF protection)
      if ip.start_with?('127.') ||              # Loopback (127.0.0.0/8)
         ip.start_with?('10.') ||               # Private class A (10.0.0.0/8)
         ip.match?(/^172\.(1[6-9]|2\d|3[01])\./) || # Private class B (172.16.0.0/12)
         ip.start_with?('192.168.') ||          # Private class C (192.168.0.0/16)
         ip == '0.0.0.0' ||                     # Unspecified address
         ip.start_with?('169.254.') ||          # Link-local (169.254.0.0/16)
         ip.start_with?('224.') ||              # Multicast (224.0.0.0/4)
         ip == '255.255.255.255'                # Broadcast
        raise "Remote URL hostname '#{hostname}' resolves to private IP address: #{ip}"
      end
    rescue Resolv::ResolvError => e
      raise "Cannot resolve hostname '#{hostname}': #{e.message}"
    end
  end

  # Fetch a GitLab CI template
  #
  # @param include_spec [Hash] Include specification with 'template' key
  # @return [String] Template contents
  def fetch_template_include(include_spec)
    template_name = include_spec['template']

    # Templates are stored in the GitLab repository
    # Path: lib/gitlab/ci/templates/
    unless @gitlab_templates_path
      raise "GitLab templates path not configured. Cannot fetch template: #{template_name}"
    end

    # Security: Validate template name doesn't contain traversal sequences
    if template_name.include?('..') || template_name.start_with?('/')
      raise "Invalid template name: #{template_name}. Template names cannot contain '..' or start with '/'"
    end

    # Resolve to absolute path and validate it's within templates directory
    template_path = File.expand_path(File.join(@gitlab_templates_path, template_name))
    templates_path_abs = File.expand_path(@gitlab_templates_path)

    # Fail-fast: Ensure path doesn't escape templates directory
    unless template_path.start_with?(templates_path_abs + File::SEPARATOR) || template_path == templates_path_abs
      raise "Template path escapes templates directory: #{template_name}"
    end

    # Fail-fast: Check if template exists
    unless File.exist?(template_path)
      raise "GitLab CI template not found: #{template_name}"
    end

    File.read(template_path)
  end

  # Fetch a project include
  #
  # @param include_spec [Hash] Include specification with 'project', 'file', 'ref' keys
  # @return [String] File contents
  def fetch_project_include(include_spec)
    project = include_spec['project']
    file = include_spec['file'] || '.gitlab-ci.yml'
    ref = include_spec['ref'] # Optional - not implemented for local file system

    # Security: Validate project and file paths don't contain traversal sequences
    if project.include?('..') || project.start_with?('/')
      raise "Invalid project path: #{project}. Cannot contain '..' or start with '/'"
    end

    if file.include?('..') || file.start_with?('/')
      raise "Invalid file path: #{file}. Cannot contain '..' or start with '/'"
    end

    # For local filesystem simulation, resolve project path
    # Use parent directory of current project as base
    base_dir = @project_path ? File.dirname(File.expand_path(@project_path)) : File.expand_path('..')
    project_path = File.expand_path(File.join(base_dir, project))
    base_dir_abs = File.expand_path(base_dir)

    # Fail-fast: Validate project path is within allowed directory
    unless project_path.start_with?(base_dir_abs + File::SEPARATOR) || project_path == base_dir_abs
      raise "Project path escapes allowed directory: #{project}"
    end

    # Fail-fast: Check if project directory exists
    unless Dir.exist?(project_path)
      raise "Project not found: #{project}"
    end

    file_path = File.expand_path(File.join(project_path, file))

    # Fail-fast: Validate file path is within project directory
    unless file_path.start_with?(project_path + File::SEPARATOR) || file_path == project_path
      raise "File path escapes project directory: #{file}"
    end

    # Fail-fast: Check if file exists
    unless File.exist?(file_path)
      raise "File not found in project #{project}: #{file}"
    end

    File.read(file_path)
  end

  # Fetch a component include
  #
  # @param include_spec [Hash] Include specification with 'component' key
  # @return [String] Component contents
  def fetch_component_include(include_spec)
    component_ref = include_spec['component']

    # Component syntax: <project>@<version>/<component>
    # Example: gitlab.com/components/docker@1.0.0/build.yml
    # This is a GitLab 16.0+ feature

    # For now, components are not fully implemented
    # They would require catalog API access
    raise "Component includes are not yet supported: #{component_ref}. " \
          "Components are a GitLab 16.0+ feature requiring catalog API access."
  end

  # Deep merge two configuration hashes
  #
  # @param base [Hash] Base configuration
  # @param overlay [Hash] Configuration to merge on top
  # @return [Hash] Merged configuration
  def deep_merge(base, overlay)
    result = base.dup

    overlay.each do |key, value|
      if result[key].is_a?(Hash) && value.is_a?(Hash)
        # Recursively merge nested hashes
        result[key] = deep_merge(result[key], value)
      else
        # For arrays and primitives, overlay replaces base
        # This matches GitLab's include behavior
        result[key] = value
      end
    end

    result
  end

  # Generate unique identifier for an include to detect circular references
  #
  # @param include_spec [Hash, String] Include specification
  # @return [String] Unique identifier
  def include_identifier(include_spec)
    if include_spec.is_a?(String)
      # Local include as string
      return "local:#{File.expand_path(File.join(@project_path, include_spec))}"
    end

    # Detect type and build identifier
    if include_spec.key?('local')
      "local:#{File.expand_path(File.join(@project_path, include_spec['local']))}"
    elsif include_spec.key?('remote')
      "remote:#{include_spec['remote']}"
    elsif include_spec.key?('template')
      "template:#{include_spec['template']}"
    elsif include_spec.key?('project')
      project = include_spec['project']
      file = include_spec['file'] || '.gitlab-ci.yml'
      ref = include_spec['ref'] || 'HEAD'
      "project:#{project}:#{file}:#{ref}"
    elsif include_spec.key?('component')
      "component:#{include_spec['component']}"
    else
      raise "Cannot generate identifier for include spec: #{include_spec.inspect}"
    end
  end
end
