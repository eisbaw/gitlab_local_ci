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
require_relative 'external_resource_cache'
require_relative 'rules_evaluator'

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

  attr_reader :project_path, :gitlab_templates_path, :variables

  # Initialize the include processor
  #
  # @param project_path [String] Path to the project root
  # @param gitlab_templates_path [String] Path to GitLab templates directory
  # @param cache_root [String] Root directory for external resource cache
  # @param variables [Hash] CI variables used to evaluate `include: rules: if:`
  #   expressions. Pipeline-trigger variables (i.e. those passed via
  #   `--variables`) belong here; defaults from a top-level `variables:` block
  #   are NOT visible to include rules (matches GitLab documented behavior).
  def initialize(project_path:, gitlab_templates_path: nil, cache_root: 'ext_tmp', variables: {})
    @project_path = project_path
    @gitlab_templates_path = gitlab_templates_path
    @processed_includes = Set.new # Track processed includes to detect circular refs
    @external_cache = ExternalResourceCache.new(cache_root: cache_root)
    @variables = variables || {}
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

    # Expand project includes with array file specs into multiple includes
    includes = expand_array_file_includes(includes)

    # Start with base config (without include key)
    result = config.dup
    result.delete('include')

    # Process each include
    includes.each do |include_spec|
      # GitLab evaluates `include: rules:` against pipeline-trigger
      # variables BEFORE fetching the include. Skip non-matching includes
      # entirely; never resolve their files, never merge their content.
      next unless include_rules_match?(include_spec)

      # Determine include type and fetch content
      include_type = determine_include_type(include_spec)

      # Generate identifier for circular detection
      identifier = include_identifier(include_spec)

      if @processed_includes.include?(identifier)
        raise StandardError, "Circular include detected: #{identifier}"
      end

      @processed_includes.add(identifier)

      begin
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
      ensure
        # Always cleanup, even if exception occurs
        @processed_includes.delete(identifier)
      end
    end

    result
  end

  private

  # Evaluate `rules:` on an include spec.
  #
  # GitLab semantics: the include is merged iff a rule matches and that
  # rule's `when:` is not `never`. Specs without a `rules:` key are merged
  # unconditionally. String specs cannot carry rules at all.
  #
  # @param include_spec [Hash, String] Single include specification.
  # @return [Boolean] True if the include should be merged.
  def include_rules_match?(include_spec)
    return true unless include_spec.is_a?(Hash)

    rules = include_spec['rules'] || include_spec[:rules]
    return true if rules.nil?

    # Include rules use mode: :include so RulesEvaluator validates that
    # `when:` is one of {never, always} (matches upstream
    # gitlab/lib/gitlab/ci/config/external/rules.rb ALLOWED_WHEN).
    context = { project_dir: @project_path, default_branch: ENV['CI_DEFAULT_BRANCH'] || 'main' }
    result = RulesEvaluator.evaluate_rules(rules, @variables, context: context, mode: :include)
    return false unless result[:matched]

    when_clause = result[:when]
    return false if when_clause && when_clause.to_s == 'never'

    true
  end

  # Expand includes with array file specs into multiple individual includes
  #
  # @param includes [Array<Hash>] Array of include specifications
  # @return [Array<Hash>] Expanded array with array files converted to multiple includes
  def expand_array_file_includes(includes)
    expanded = []

    includes.each do |include_spec|
      # Check if this is a project/file include with array file spec
      if include_spec.is_a?(Hash) &&
         (include_spec.key?('project') || include_spec.key?('file')) &&
         include_spec['file'].is_a?(Array)

        # Expand into multiple includes, one per file
        include_spec['file'].each do |single_file|
          expanded_spec = include_spec.dup
          expanded_spec['file'] = single_file
          expanded << expanded_spec
        end
      elsif include_spec.is_a?(Hash) && include_spec.key?('local')
        # Check if local include has glob pattern
        local_path = include_spec['local']
        if local_path.include?('*')
          # Expand glob pattern
          expanded_includes = expand_local_glob(local_path)
          expanded_includes.each do |file_path|
            expanded_spec = include_spec.dup
            expanded_spec['local'] = file_path
            expanded << expanded_spec
          end
        else
          # No glob, keep as-is
          expanded << include_spec
        end
      elsif include_spec.is_a?(String) && include_spec.include?('*')
        # String local include with glob
        expanded_includes = expand_local_glob(include_spec)
        expanded.concat(expanded_includes)
      else
        # Not an array file spec or glob, keep as-is
        expanded << include_spec
      end
    end

    expanded
  end

  # Expand glob pattern in local include path
  #
  # @param pattern [String] Glob pattern (may contain * or **)
  # @return [Array<String>] Array of matched file paths
  def expand_local_glob(pattern)
    # Strip leading slash if present (GitLab treats /path as repo-root-relative)
    normalized_pattern = pattern.start_with?('/') ? pattern[1..-1] : pattern

    # Security: Ensure pattern doesn't escape project directory
    if normalized_pattern.include?('..')
      raise "Invalid glob pattern: #{pattern}. Pattern cannot contain '..'"
    end

    # Build full glob pattern
    full_pattern = File.join(@project_path, normalized_pattern)

    # Find matching files
    matches = Dir.glob(full_pattern).select { |path| File.file?(path) }

    # Convert back to project-relative paths
    project_path_abs = File.expand_path(@project_path)
    matches.map do |match|
      File.expand_path(match).sub("#{project_path_abs}/", '')
    end.sort
  end

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

    # Security: Validate path doesn't contain traversal sequences
    if file_path.include?('..')
      raise "Invalid local include path: #{file_path}. Path cannot contain '..'"
    end

    # GitLab CI treats paths starting with '/' as repository-root-relative,
    # not absolute filesystem paths. Strip leading slash to normalize.
    normalized_path = file_path.start_with?('/') ? file_path[1..-1] : file_path

    # Resolve to absolute path and validate it's within project
    full_path = File.expand_path(File.join(@project_path, normalized_path))
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

    # Security: Validate template name doesn't contain traversal sequences
    if template_name.include?('..')
      raise "Invalid template name: #{template_name}. Template names cannot contain '..'"
    end

    # Strip leading slash if present (normalize path)
    template_name = template_name.sub(%r{^/}, '')

    # Use external cache to fetch template
    # This will:
    # 1. Check local gitlab_templates_path if available
    # 2. Check cache (ext_tmp/templates/)
    # 3. Download from gitlab.com if needed
    @external_cache.fetch_template(template_name, gitlab_templates_path: @gitlab_templates_path)
  rescue StandardError => e
    raise "Failed to fetch template '#{template_name}': #{e.message}"
  end

  # Fetch a project include
  #
  # @param include_spec [Hash] Include specification with 'project', 'file', 'ref' keys
  # @return [String] File contents
  def fetch_project_include(include_spec)
    project = include_spec['project']
    file = include_spec['file'] || '.gitlab-ci.yml'
    ref = include_spec['ref'] || 'master'

    # Security: Validate project and file paths don't contain traversal sequences
    if project.include?('..')
      raise "Invalid project path: #{project}. Cannot contain '..'"
    end

    if file.include?('..')
      raise "Invalid file path: #{file}. Cannot contain '..'"
    end

    # Normalize paths (strip leading slashes)
    project = project.sub(%r{^/}, '')
    file = file.sub(%r{^/}, '')

    # Try local filesystem first
    content = try_fetch_local_project_file(project, file)
    return content if content

    # If not found locally, download from gitlab.com
    @external_cache.fetch_project_file(project, file, ref: ref)
  rescue StandardError => e
    raise "Failed to fetch file '#{file}' from project '#{project}': #{e.message}"
  end

  # Try to fetch project file from local filesystem
  #
  # @param project [String] Project path
  # @param file [String] File path
  # @return [String, nil] File content or nil if not found
  def try_fetch_local_project_file(project, file)
    # For local filesystem simulation, resolve project path
    # Use parent directory of current project as base
    base_dir = @project_path ? File.dirname(File.expand_path(@project_path)) : File.expand_path('..')
    project_path = File.expand_path(File.join(base_dir, project))
    base_dir_abs = File.expand_path(base_dir)

    # Validate project path is within allowed directory
    unless project_path.start_with?(base_dir_abs + File::SEPARATOR) || project_path == base_dir_abs
      return nil # Invalid path, skip local lookup
    end

    # Check if project directory exists
    return nil unless Dir.exist?(project_path)

    file_path = File.expand_path(File.join(project_path, file))

    # Validate file path is within project directory
    unless file_path.start_with?(project_path + File::SEPARATOR) || file_path == project_path
      return nil # Invalid path, skip local lookup
    end

    # Check if file exists
    return nil unless File.exist?(file_path)

    File.read(file_path)
  rescue StandardError
    # Any error in local lookup, return nil to try remote
    nil
  end

  # Fetch a component include
  #
  # @param include_spec [Hash] Include specification with 'component' key
  # @return [String] Component contents
  def fetch_component_include(include_spec)
    component_ref = include_spec['component']
    inputs = include_spec['inputs'] || {}

    # Component syntax: <fqdn>/<project-path>@<version>
    # Example: gitlab.com/gitlab-org/components/danger-review@2.0.0
    # The component template is assumed to be at templates/<component-name>.yml

    # Expand CI variables in component reference
    expanded_ref = expand_ci_variables(component_ref)

    # Parse component reference: <fqdn>/<project-parts>@<version>
    match = expanded_ref.match(%r{^([^/]+)/(.+)@([^/@]+)$})
    unless match
      raise "Invalid component reference format: #{component_ref}. " \
            "Expected format: <fqdn>/<project-path>@<version>"
    end

    fqdn = match[1]
    full_path = match[2]  # e.g., "gitlab-org/components/danger-review/danger-review"
    version = match[3]

    # For components, the full path IS the project path
    # Component file is typically template.yml at the root
    project_path = full_path
    component_file = "template.yml"

    # Use external cache with the specific GitLab instance
    @external_cache.fetch_component(fqdn, project_path, component_file, version)
  rescue StandardError => e
    raise "Failed to fetch component '#{component_ref}': #{e.message}"
  end

  # Expand CI variables in a string
  #
  # @param string [String] String potentially containing CI variables
  # @return [String] String with variables expanded
  def expand_ci_variables(string)
    # Common CI variables
    ci_vars = {
      'CI_SERVER_FQDN' => ENV['CI_SERVER_FQDN'] || 'gitlab.com',
      'CI_SERVER_HOST' => ENV['CI_SERVER_HOST'] || 'gitlab.com',
      'CI_SERVER_URL' => ENV['CI_SERVER_URL'] || 'https://gitlab.com'
    }

    result = string.dup
    ci_vars.each do |var_name, var_value|
      result.gsub!("${#{var_name}}", var_value)
      result.gsub!("$#{var_name}", var_value)
    end

    result
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
