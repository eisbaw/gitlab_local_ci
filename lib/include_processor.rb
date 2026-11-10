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

require_relative 'ci_yaml'
require 'net/http'
require 'uri'
require 'set'
require_relative 'external_resource_cache'
require_relative 'public_address'
require_relative 'rules_evaluator'
require_relative 'config_merge'
require_relative 'predefined_variables'

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
  # @param gitlab_templates_path [String, nil] GitLab checkout's
  #   lib/gitlab/ci/templates; may be missing, only include:template needs it
  # @param cache_root [String] Root directory for external resource cache
  # @param variables [Hash] CI variables used to evaluate `include: rules: if:`
  #   expressions. Pipeline-trigger variables (i.e. those passed via
  #   `--variables`) belong here; defaults from a top-level `variables:` block
  #   are NOT visible to include rules (matches GitLab documented behavior).
  # @param server_url [String] the GitLab instance include:project is
  #   fetched from (PredefinedVariables.server_url)
  def initialize(project_path:, gitlab_templates_path: nil, cache_root: 'ext_tmp', variables: {},
                 server_url: PredefinedVariables::SERVER_URL_FALLBACK)
    @project_path = project_path
    @gitlab_templates_path = gitlab_templates_path
    @processed_includes = Set.new # Track processed includes to detect circular refs
    @external_cache = ExternalResourceCache.new(cache_root: cache_root)
    @variables = variables || {}
    @server_url = server_url
    @projects_read_locally = Set.new
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

    # Upstream External::Processor#perform: merge included files in order
    # (later include wins), then merge the including file on top (it wins).
    merged_includes = {}

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
        included_config = CiYaml.load(content)

        # Recursively process includes in the included file
        included_config = process_includes(included_config, depth + 1)

        merged_includes = ConfigMerge.deep_merge(merged_includes, included_config)
      ensure
        # Always cleanup, even if exception occurs
        @processed_includes.delete(identifier)
      end
    end

    ConfigMerge.deep_merge(merged_includes, config.reject { |key, _| key == 'include' })
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

    # Upstream Entry::Include::Rules is a ComposableArray: [config].flatten,
    # so a YAML alias used as one rule contributes its rules.
    rules = rules.flatten if rules.is_a?(Array)

    # Include rules use mode: :include so RulesEvaluator validates that
    # `when:` is one of {never, always} (matches upstream
    # gitlab/lib/gitlab/ci/config/external/rules.rb ALLOWED_WHEN).
    # The builder's variable set (predefined + CLI), like workflow and job
    # rules; never the ambient environment.
    context = { project_dir: @project_path, default_branch: @variables['CI_DEFAULT_BRANCH'] || 'main' }
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

    # Validate and parse URL; address is the vetted public IP to connect to
    uri, address = validate_remote_url(url_string)

    # Connect to the vetted address, not to whatever a second DNS lookup
    # returns: Net::HTTP would resolve the name again, and an answer that
    # changed in between (DNS rebinding) would bypass the check. ipaddr only
    # changes the TCP peer; the Host header, SNI and the certificate check
    # still use uri.hostname. Timeouts bound a slow or silent server.
    response = Net::HTTP.start(
      uri.hostname,
      uri.port,
      ipaddr: address,
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
  # @return [Array(URI, String)] parsed URI, and the public IP address to
  #   connect to
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

    # After the allowlist, so a host it rejects is never looked up.
    # SSRF protection: a config must not make this tool talk to services on
    # this machine or its network (cloud metadata, admin ports). The caller
    # connects to the returned address only.
    address = PublicAddress.resolve!(uri.hostname)

    [uri, address]
  rescue URI::InvalidURIError => e
    raise "Invalid remote URL: #{url_string} - #{e.message}"
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

    # The checkout is the pinned template source. Without it the cache
    # would fall back to gitlab.com master, a different template version
    # than the one the rest of the tool is checked against, so fail here
    # and say how to point at one.
    unless @gitlab_templates_path && Dir.exist?(@gitlab_templates_path)
      where = @gitlab_templates_path ? "'#{@gitlab_templates_path}' not found" : 'no GitLab checkout configured'
      raise "include:template needs a GitLab source checkout (#{where}); pass --gitlab-dir <path to gitlab repo>"
    end

    # Checkout first; ext_tmp/ cache and gitlab.com only for a template the
    # checkout does not have (e.g. one newer than it).
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

    # Not a valid git ref either (git check-ref-format), and the ref is a
    # directory of the download cache path.
    if ref.include?('..')
      raise "Invalid ref: #{ref}. Cannot contain '..'"
    end

    # Normalize paths (strip leading slashes)
    project = project.sub(%r{^/}, '')
    file = file.sub(%r{^/}, '')

    # Try local filesystem first
    content = try_fetch_local_project_file(project, file, include_spec['ref'])
    return content if content

    # Else the one GitLab instance this pipeline runs on (never a fan-out:
    # a private project path must not reach unrelated hosts)
    @external_cache.fetch_project_file(project, file, ref: ref, server_url: @server_url)
  rescue StandardError => e
    raise "Failed to fetch file '#{file}' from project '#{project}': #{e.message}"
  end

  # Read a project file from a sibling checkout, ../<project>/<file> next to
  # the project directory, if there is one: a local working copy of an
  # included project (e.g. ci-templates being edited) wins over the network.
  # It is the working tree, whatever is checked out there, so `ref:` is NOT
  # honoured; a warning says so once per project. Honouring it (git show
  # ref:file) would break that use, and fail for refs never fetched there.
  #
  # @param project [String] Project path
  # @param file [String] File path
  # @param ref [String, nil] the include's ref:, for the warning only
  # @return [String, nil] File content, nil when there is no such sibling
  #   file (then the caller fetches it). A read error is raised, not nil:
  #   it must not silently turn into a network request.
  def try_fetch_local_project_file(project, file, ref)
    base_dir = @project_path ? File.dirname(File.expand_path(@project_path)) : File.expand_path('..')
    project_path = File.expand_path(File.join(base_dir, project))

    # Callers reject '..'; this is the negative-space check that the
    # sibling stays under base_dir anyway.
    return nil unless project_path.start_with?(base_dir + File::SEPARATOR)
    return nil unless Dir.exist?(project_path)

    file_path = File.expand_path(File.join(project_path, file))
    return nil unless file_path.start_with?(project_path + File::SEPARATOR)
    return nil unless File.file?(file_path)

    if @projects_read_locally.add?(project)
      warn "Warning: include:project '#{project}' read from the local checkout #{project_path}; " \
           "ref #{ref ? "'#{ref}'" : '(default branch)'} is not honoured"
    end
    File.read(file_path)
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
    @external_cache.fetch_component(fqdn, project_path, component_file, version, instance_url: @server_url)
  rescue StandardError => e
    raise "Failed to fetch component '#{component_ref}': #{e.message}"
  end

  # Expand $CI_SERVER_URL, $CI_SERVER_HOST and $CI_SERVER_FQDN (also ${...})
  # in an include path. From the builder's variable set, never from this
  # process's environment: running the tool inside a CI job on another
  # instance must not change what a config resolves to. CI_SERVER_URL is
  # the instance include:project uses (@server_url, TASK-75), so both agree;
  # HOST and FQDN are taken from --variables when set, else derived from
  # that URL as upstream does (FQDN carries a non-default port).
  #
  # @param string [String] String potentially containing CI variables
  # @return [String] String with variables expanded
  def expand_ci_variables(string)
    values = server_variables
    string.gsub(/\$\{(CI_SERVER_(?:URL|HOST|FQDN))\}|\$(CI_SERVER_(?:URL|HOST|FQDN))\b/) do
      values.fetch(Regexp.last_match(1) || Regexp.last_match(2))
    end
  end

  # @return [Hash{String=>String}] CI_SERVER_URL, _HOST, _FQDN
  def server_variables
    uri = URI.parse(@server_url.to_s)
    raise "CI_SERVER_URL #{@server_url.inspect} has no host" if uri.host.nil? || uri.host.empty?

    fqdn = uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
    {
      'CI_SERVER_URL' => @server_url,
      'CI_SERVER_HOST' => @variables['CI_SERVER_HOST'] || uri.host,
      'CI_SERVER_FQDN' => @variables['CI_SERVER_FQDN'] || fqdn
    }
  rescue URI::InvalidURIError => e
    raise "CI_SERVER_URL #{@server_url.inspect} is not a URL: #{e.message}"
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
