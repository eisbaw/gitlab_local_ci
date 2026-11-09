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
require_relative '../extends_resolver'
require_relative '../pipeline_builder'

module Commands
  # LintCommand validates GitLab CI YAML configuration using standalone validation
  #
  # This command is a pure function: options in, result out.
  # It reads the YAML file, validates structure and semantics,
  # and returns structured data for the formatter to render.
  #
  # MPED Principles Applied:
  # - Pure function design: no global state, explicit inputs/outputs
  # - Fail fast: explicit error handling with clear error messages
  # - Minimal dependencies: uses only Ruby stdlib + YAML parsing
  # - Composable: returns data structure that formatters can transform
  # - Fundamentals first: implements validation logic directly
  class LintCommand
    # Valid job keywords according to GitLab CI schema
    VALID_JOB_KEYWORDS = %w[
      script stage needs dependencies artifacts cache image services
      before_script after_script variables allow_failure when timeout
      retry parallel tags only except rules extends environment
      resource_group release coverage interruptible trigger inherit
      pages secrets id_tokens hooks
    ].freeze

    # Result object for lint command output
    # Using a data class to make the return value explicit and typed
    class Result
      attr_reader :valid, :stages, :jobs, :errors, :warnings, :exit_code

      # Create a new result object
      #
      # @param valid [Boolean] Whether the configuration is valid
      # @param stages [Array<String>] List of stages (empty if invalid)
      # @param jobs [Array<String>] List of job names (empty if invalid)
      # @param errors [Array<String>] List of error messages (empty if valid)
      # @param warnings [Array<String>] List of warning messages
      # @param exit_code [Integer] Exit code (0 for success, 1 for failure)
      def initialize(valid:, stages: [], jobs: [], errors: [], warnings: [], exit_code: 0)
        @valid = valid
        @stages = stages
        @jobs = jobs
        @errors = errors
        @warnings = warnings
        @exit_code = exit_code
      end

      # Convert result to hash for formatter consumption
      #
      # @return [Hash] Result data as hash
      def to_h
        {
          valid: @valid,
          stages: @stages,
          jobs: @jobs,
          errors: @errors,
          warnings: @warnings
        }
      end
    end

    # Execute the lint command
    #
    # @param options [Hash] Command options
    # @option options [String] :entry Path to .gitlab-ci.yml file
    # @option options [String] :gitlab_dir Path to GitLab submodule (not used in standalone mode)
    # @option options [String] :ref Git reference to validate against (default: HEAD)
    # @option options [Hash] :variables CI variables to use in validation
    # @return [Result] Validation result
    def self.execute(options)
      new(options).execute
    end

    def initialize(options)
      @options = options
      @entry_path = options[:entry] || '.gitlab-ci.yml'
      @gitlab_dir = options[:gitlab_dir] || './gitlab'
      @ref = options[:ref] || 'HEAD'
      @variables = options[:variables] || {}
    end

    # Execute the lint validation
    #
    # @return [Result] Validation result
    def execute
      # Step 1: Validate input file exists and read content
      file_content = read_yaml_file(@entry_path)
      return file_content if file_content.is_a?(Result) # Early return on file error

      # Step 2: Parse YAML
      config = parse_yaml(file_content)
      return config if config.is_a?(Result) # Early return on parse error

      # Step 3: Process includes to merge external configurations
      config = process_includes(config)
      return config if config.is_a?(Result) # Early return on include error

      # Step 4: Resolve extends directives
      config = resolve_extends(config)
      return config if config.is_a?(Result) # Early return on extends error

      # Step 5: Validate configuration structure
      validate_configuration(config)
    rescue StandardError => e
      # Catch any unexpected errors and return them as validation failures
      # This ensures we never crash silently
      Result.new(
        valid: false,
        errors: ["Unexpected error: #{e.class.name} - #{e.message}"],
        exit_code: 1
      )
    end

    private

    # Read YAML file from disk
    #
    # @param path [String] Path to YAML file
    # @return [String, Result] File content or error result
    def read_yaml_file(path)
      unless File.exist?(path)
        return Result.new(
          valid: false,
          errors: ["File not found: #{path}"],
          exit_code: 1
        )
      end

      begin
        File.read(path)
      rescue Errno::EACCES => e
        Result.new(
          valid: false,
          errors: ["Permission denied reading file: #{path}"],
          exit_code: 1
        )
      rescue StandardError => e
        Result.new(
          valid: false,
          errors: ["Error reading file #{path}: #{e.message}"],
          exit_code: 1
        )
      end
    end

    # Parse YAML configuration
    #
    # @param content [String] YAML content
    # @return [Hash, Result] Parsed configuration or error result
    def parse_yaml(content)
      YAML.safe_load(content, permitted_classes: [Symbol], aliases: true)
    rescue Psych::SyntaxError => e
      Result.new(
        valid: false,
        errors: ["YAML syntax error: #{e.message}"],
        exit_code: 1
      )
    rescue StandardError => e
      Result.new(
        valid: false,
        errors: ["Failed to parse YAML: #{e.message}"],
        exit_code: 1
      )
    end

    # Process include directives in the configuration
    #
    # @param config [Hash] Parsed YAML configuration
    # @return [Hash, Result] Merged configuration with includes or error result
    def process_includes(config)
      return config unless config['include']

      PipelineBuilder.process_includes(
        config,
        project_dir: File.dirname(File.expand_path(@entry_path)),
        gitlab_dir: @gitlab_dir,
        variables: @variables || {}
      )
    rescue IncludeDepthExceededError => e
      Result.new(
        valid: false,
        errors: ["Include depth exceeded: #{e.depth} > #{e.max_depth}"],
        exit_code: 1
      )
    rescue StandardError => e
      Result.new(
        valid: false,
        errors: ["Error processing includes: #{e.message}"],
        exit_code: 1
      )
    end

    # Resolve extends directives in the configuration
    #
    # @param config [Hash] Configuration with includes resolved
    # @return [Hash, Result] Configuration with extends resolved or error result
    def resolve_extends(config)
      resolver = ExtendsResolver.new
      resolver.resolve_extends(config)
    rescue StandardError => e
      Result.new(
        valid: false,
        errors: ["Error resolving extends: #{e.message}"],
        exit_code: 1
      )
    end

    # Validate the configuration structure and semantics
    #
    # @param config [Hash] Parsed YAML configuration
    # @return [Result] Validation result
    def validate_configuration(config)
      errors = []
      warnings = []

      # Validate that config is a hash
      unless config.is_a?(Hash)
        return Result.new(
          valid: false,
          errors: ["Configuration must be a YAML hash/dictionary"],
          exit_code: 1
        )
      end

      # Extract stages (default to standard GitLab stages if not specified)
      stages = config['stages'] || %w[build test deploy]

      # Collect all jobs
      jobs = PipelineBuilder.job_definitions(config)

      # Validate there's at least one job
      if jobs.empty?
        errors << "No jobs defined in configuration"
      end

      # Validate each job
      jobs.each do |job_name, job_config|
        validate_job(job_name, job_config, stages, jobs.keys, errors, warnings)
      end

      # Check for circular dependencies in needs
      check_circular_dependencies(jobs, errors)

      # Build result
      if errors.empty?
        Result.new(
          valid: true,
          stages: stages,
          jobs: jobs.keys,
          errors: [],
          warnings: warnings,
          exit_code: 0
        )
      else
        Result.new(
          valid: false,
          stages: [],
          jobs: [],
          errors: errors,
          warnings: warnings,
          exit_code: 1
        )
      end
    end

    # Validate a single job configuration
    #
    # @param job_name [String] Name of the job
    # @param job_config [Hash] Job configuration
    # @param stages [Array<String>] Valid stages
    # @param all_job_names [Array<String>] All job names for needs validation
    # @param errors [Array<String>] Accumulator for error messages
    # @param warnings [Array<String>] Accumulator for warning messages
    def validate_job(job_name, job_config, stages, all_job_names, errors, warnings)
      # Check for invalid job keywords
      job_config.each_key do |key|
        unless VALID_JOB_KEYWORDS.include?(key)
          warnings << "Job '#{job_name}' uses non-standard keyword: #{key}"
        end
      end

      # Validate script or trigger is present (one of them is required)
      # Template jobs (starting with .) don't need scripts
      unless job_name.start_with?('.') || job_config['script'] || job_config['trigger'] || job_config['pages']
        errors << "Job '#{job_name}' must have 'script', 'trigger', or 'pages' defined"
      end

      # Validate script format if present
      if job_config['script']
        validate_script(job_name, job_config['script'], errors)
      end

      # Validate stage reference if present (skip for template jobs)
      if job_config['stage'] && !job_name.start_with?('.')
        stage = job_config['stage']
        unless stages.include?(stage)
          errors << "Job '#{job_name}' references undefined stage '#{stage}'"
        end
      end

      # Validate needs dependencies (skip for template jobs)
      if job_config['needs'] && !job_name.start_with?('.')
        validate_needs(job_name, job_config['needs'], all_job_names, errors)
      end

      # Validate extends references
      if job_config['extends']
        validate_extends(job_name, job_config['extends'], all_job_names, errors, warnings)
      end

      # Warn about hidden jobs (templates starting with .)
      if job_name.start_with?('.')
        warnings << "Job '#{job_name}' is a hidden job template (starts with '.')"
      end
    end

    # Validate script configuration
    #
    # @param job_name [String] Job name for error messages
    # @param script [Object] Script configuration
    # @param errors [Array<String>] Error accumulator
    def validate_script(job_name, script, errors)
      # Script can be array or string
      unless script.is_a?(Array) || script.is_a?(String)
        errors << "Job '#{job_name}' has invalid script format (must be string or array)"
      end

      # If array, check it's not empty
      if script.is_a?(Array) && script.empty?
        errors << "Job '#{job_name}' has empty script array"
      end
    end

    # Validate needs dependencies
    #
    # @param job_name [String] Job name for error messages
    # @param needs [Object] Needs configuration
    # @param all_job_names [Array<String>] All job names for reference checking
    # @param errors [Array<String>] Error accumulator
    def validate_needs(job_name, needs, all_job_names, errors)
      unless needs.is_a?(Array)
        errors << "Job '#{job_name}' has invalid needs format (must be array)"
        return
      end

      needs.each do |need|
        # Skip YAML reference tags (parsed as arrays like [".template", "needs"])
        # These are GitLab's !reference syntax that gets resolved at runtime
        if need.is_a?(Array) && need.length == 2 && need[0].is_a?(String) && need[1].is_a?(String)
          next
        end

        # Needs can be string (job name) or hash (with job key)
        needed_job = case need
                     when String
                       need
                     when Hash
                       need['job']
                     else
                       nil
                     end

        if needed_job.nil?
          errors << "Job '#{job_name}' has invalid needs entry: #{need.inspect}"
        elsif !all_job_names.include?(needed_job)
          # Skip validation for jobs with slashes - these are from external project includes
          unless needed_job.include?('/')
            errors << "Job '#{job_name}' needs undefined job '#{needed_job}'"
          end
        end
      end
    end

    # Validate extends references
    #
    # @param job_name [String] Job name for error messages
    # @param extends [Object] Extends configuration
    # @param all_job_names [Array<String>] All job names for reference checking
    # @param errors [Array<String>] Error accumulator
    # @param warnings [Array<String>] Warning accumulator
    def validate_extends(job_name, extends, all_job_names, errors, warnings)
      # Extends can be string or array of strings
      extends_list = case extends
                     when String
                       [extends]
                     when Array
                       extends
                     else
                       []
                     end

      extends_list.each do |template|
        # Check if template exists (should start with . for templates)
        unless template.start_with?('.')
          warnings << "Job '#{job_name}' extends non-hidden job '#{template}' (consider using '.' prefix for templates)"
        end

        unless all_job_names.include?(template)
          errors << "Job '#{job_name}' extends undefined template '#{template}'"
        end
      end
    end

    # Check for circular dependencies in needs
    #
    # Uses depth-first search to detect cycles
    #
    # @param jobs [Hash] All jobs with their configurations
    # @param errors [Array<String>] Error accumulator
    def check_circular_dependencies(jobs, errors)
      # Build adjacency list
      visited = {}
      rec_stack = {}

      jobs.each_key do |job_name|
        next if visited[job_name]

        if has_cycle?(job_name, jobs, visited, rec_stack)
          errors << "Circular dependency detected involving job '#{job_name}'"
        end
      end
    end

    # Detect cycle using DFS
    #
    # @param job_name [String] Current job being checked
    # @param jobs [Hash] All jobs
    # @param visited [Hash] Tracking of visited nodes
    # @param rec_stack [Hash] Tracking of recursion stack for cycle detection
    # @return [Boolean] true if cycle detected
    def has_cycle?(job_name, jobs, visited, rec_stack)
      visited[job_name] = true
      rec_stack[job_name] = true

      job = jobs[job_name]
      if job && job['needs']
        needs = extract_needs_list(job['needs'])

        needs.each do |dependency|
          next unless jobs[dependency]

          if !visited[dependency]
            return true if has_cycle?(dependency, jobs, visited, rec_stack)
          elsif rec_stack[dependency]
            # Found a back edge - cycle detected
            return true
          end
        end
      end

      # Remove from recursion stack before returning
      rec_stack[job_name] = false
      false
    end

    # Extract needs as simple array of job names
    #
    # @param needs [Array] Needs configuration
    # @return [Array<String>] Job names
    def extract_needs_list(needs)
      return [] unless needs.is_a?(Array)

      needs.map do |need|
        case need
        when String
          need
        when Hash
          need['job']
        else
          nil
        end
      end.compact
    end
  end
end
