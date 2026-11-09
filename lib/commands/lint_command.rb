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
      @context = PipelineBuilder::Context.from_options(options.merge(entry: @entry_path, gitlab_dir: @gitlab_dir))
    end

    # Execute the lint validation
    #
    # @return [Result] Validation result
    def execute
      # Static config (load, includes, extends); lint does not evaluate rules
      resolved = PipelineBuilder.resolve_config(@entry_path, @context)
      return Result.new(valid: false, errors: resolved.errors, exit_code: 1) unless resolved.ok?

      validate_configuration(resolved)
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

    # Validate the configuration structure and semantics
    #
    # @param resolved [PipelineBuilder::Result] resolved static config
    # @return [Result] Validation result
    def validate_configuration(resolved)
      errors = []
      warnings = []

      stages = resolved.stages

      # Visible jobs only: a hidden key ('.foo') is upstream Entry::Hidden,
      # not a job. It is neither listed, counted nor validated as one (it is
      # never Entry::Job, so job validations never see it).
      jobs = resolved.jobs

      # Validate there's at least one (visible) job
      if jobs.empty?
        errors << "No jobs defined in configuration"
      end

      # Validate each job
      jobs.each do |job_name, job_config|
        validate_job(job_name, job_config, jobs.keys, errors, warnings)
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
    # @param all_job_names [Array<String>] All job names for needs validation
    # @param errors [Array<String>] Accumulator for error messages
    # @param warnings [Array<String>] Accumulator for warning messages
    def validate_job(job_name, job_config, all_job_names, errors, warnings)
      # Check for invalid job keywords
      job_config.each_key do |key|
        unless CiKeywords::JOB.include?(key)
          warnings << "Job '#{job_name}' uses non-standard keyword: #{key}"
        end
      end

      # Validate script or trigger is present (one of them is required)
      unless job_config['script'] || job_config['trigger'] || job_config['pages']
        errors << "Job '#{job_name}' must have 'script', 'trigger', or 'pages' defined"
      end

      # Validate script format if present
      if job_config['script']
        validate_script(job_name, job_config['script'], errors)
      end

      # Stages are checked once for every command, in
      # PipelineBuilder.stage_errors (upstream YamlProcessor).

      # Validate needs dependencies
      if job_config['needs']
        validate_needs(job_name, job_config['needs'], all_job_names, errors)
      end
    end

    # Validate script configuration
    #
    # @param job_name [String] Job name for error messages
    # @param script [Object] Script configuration
    # @param errors [Array<String>] Error accumulator
    def validate_script(job_name, script, errors)
      # Element types are checked once for every command, in
      # PipelineBuilder.commands_errors (upstream Entry::Commands).

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
