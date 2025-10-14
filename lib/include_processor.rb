# frozen_string_literal: true

require 'yaml'
require 'net/http'
require 'uri'

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
    # TODO: Implement include processing logic
    # - Check if depth > MAX_DEPTH, raise IncludeDepthExceededError if exceeded
    # - Extract 'include' key from config
    # - Return config as-is if no includes present
    # - Normalize include to array (handle single include or array of includes)
    # - Iterate each include_spec:
    #   * Determine include type (local, file, remote, template, project, component)
    #   * Call appropriate fetch method
    #   * Parse fetched content as YAML
    #   * Detect circular includes using @processed_includes
    #   * Recursively process includes in fetched content (depth + 1)
    #   * Deep merge into result config
    # - Remove 'include' key from final result
    # - Return merged configuration

    config
  end

  private

  # Determine the type of include from the spec
  #
  # @param include_spec [Hash, String] Include specification
  # @return [Symbol] Include type
  def determine_include_type(include_spec)
    # TODO: Detect include type from spec structure
    # - If String: :local
    # - If Hash with 'local' key: :local
    # - If Hash with 'file' key: :file
    # - If Hash with 'remote' key: :remote
    # - If Hash with 'template' key: :template
    # - If Hash with 'project' key: :project
    # - If Hash with 'component' key: :component
  end

  # Fetch a local include file
  #
  # @param include_spec [Hash, String] Include specification
  # @return [String] File contents
  def fetch_local_include(include_spec)
    # TODO: Implement local file inclusion
    # - Extract file path from include_spec (handle both String and Hash forms)
    # - Resolve relative to @project_path
    # - Read and return file contents
    # - Raise error if file not found
  end

  # Fetch a file include from another project
  #
  # @param include_spec [Hash] Include specification with 'project' and 'file' keys
  # @return [String] File contents
  def fetch_file_include(include_spec)
    # TODO: Implement file inclusion from another project
    # - Extract project path from include_spec['project']
    # - Extract file path from include_spec['file']
    # - Extract optional ref from include_spec['ref']
    # - Resolve project path relative to projects directory
    # - Read file from that project
    # - Return file contents
  end

  # Fetch a remote include via HTTP(S)
  #
  # @param include_spec [Hash] Include specification with 'remote' key
  # @return [String] File contents
  def fetch_remote_include(include_spec)
    # TODO: Implement remote file fetching
    # - Extract URL from include_spec['remote']
    # - Make HTTP GET request
    # - Return response body
    # - Handle HTTP errors (404, 500, etc.)
    # - Handle network errors
  end

  # Fetch a GitLab CI template
  #
  # @param include_spec [Hash] Include specification with 'template' key
  # @return [String] Template contents
  def fetch_template_include(include_spec)
    # TODO: Implement template inclusion
    # - Extract template name from include_spec['template']
    # - Look up template in @gitlab_templates_path or GitLab submodule
    # - Common templates: Auto-DevOps.gitlab-ci.yml, Security/SAST.gitlab-ci.yml
    # - Read and return template contents
    # - Raise error if template not found
  end

  # Fetch a project include
  #
  # @param include_spec [Hash] Include specification with 'project', 'file', 'ref' keys
  # @return [String] File contents
  def fetch_project_include(include_spec)
    # TODO: Implement project file inclusion
    # - Similar to fetch_file_include
    # - Extract project, file, and ref from include_spec
    # - Resolve and read file
  end

  # Fetch a component include
  #
  # @param include_spec [Hash] Include specification with 'component' key
  # @return [String] Component contents
  def fetch_component_include(include_spec)
    # TODO: Implement component inclusion (GitLab 16.0+)
    # - Extract component path from include_spec['component']
    # - Component syntax: <project>@<version>/<component>
    # - Parse component reference
    # - Fetch component from catalog
    # - Return component contents
  end

  # Deep merge two configuration hashes
  #
  # @param base [Hash] Base configuration
  # @param overlay [Hash] Configuration to merge on top
  # @return [Hash] Merged configuration
  def deep_merge(base, overlay)
    # TODO: Implement deep merge logic
    # - Handle nested hashes
    # - Arrays should be replaced, not merged
    # - Special handling for job definitions
    # - Handle extends/before_script/after_script merging rules
  end

  # Generate unique identifier for an include to detect circular references
  #
  # @param include_spec [Hash, String] Include specification
  # @return [String] Unique identifier
  def include_identifier(include_spec)
    # TODO: Generate unique ID from include spec
    # - For local: use absolute path
    # - For remote: use URL
    # - For template: use template name
    # - For project: use project + file + ref
  end
end
