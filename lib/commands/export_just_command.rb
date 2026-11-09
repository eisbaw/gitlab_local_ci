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
require 'time'

module GitlabCiCli
  module Commands
    # ExportJustCommand exports GitLab CI jobs as justfile recipes
    #
    # Generates two types of justfiles:
    # - Flat: Independent recipes without dependencies
    # - Graph: Recipes with full dependency graph
    #
    # MPED Principles Applied:
    # - Single Source of Truth: Reuses parsing logic from RunCommand
    # - Explicit: Clear output format with documentation
    # - Fail-fast: Validates jobs and dependencies
    class ExportJustCommand
      attr_reader :options

      # Initialize the export-just command
      #
      # @param options [Hash] Command options
      # @option options [String] :entry Path to .gitlab-ci.yml file
      # @option options [String] :gitlab_dir Path to GitLab submodule
      # @option options [String] :output Output filename
      # @option options [Boolean] :flat Generate flat list (no dependencies)
      # @option options [Boolean] :graph Generate with dependencies
      # @option options [String] :shell Shell to use (default: bash)
      # @option options [Hash] :variables CI variables
      # @option options [Boolean] :verbose Enable verbose output
      def initialize(options = {})
        @options = validate_options(options)
        @config = nil
        @all_jobs = nil
        @stages = nil
      end

      # Execute the export command
      #
      # @return [Integer] Exit code (0 for success, 1 for failure)
      def execute
        return 1 unless load_config

        # Generate appropriate justfile
        output = if @options[:flat]
                   generate_flat_justfile
                 else
                   generate_graph_justfile
                 end

        # Write to file or stdout
        if @options[:output]
          File.write(@options[:output], output)
          log_info("Exported justfile to: #{@options[:output]}")
        else
          puts output
        end

        0
      rescue StandardError => e
        log_error("Export failed: #{e.message}")
        log_error("Backtrace: #{e.backtrace.first(5).join("\n")}") if @options[:verbose]
        1
      end

      private

      # Validate command options
      #
      # @param options [Hash] Raw options hash
      # @return [Hash] Validated options with defaults
      def validate_options(options)
        {
          entry: options[:entry] || './.gitlab-ci.yml',
          gitlab_dir: options[:gitlab_dir] || './gitlab',
          output: options[:output],
          flat: options[:flat] || false,
          graph: options[:graph] || false,
          shell: options[:shell] || 'bash',
          variables: options[:variables] || {},
          project: options[:project],
          pipeline: options[:pipeline],
          verbose: options[:verbose] || false
        }
      end

      # Load and process configuration
      #
      # @return [Boolean] false if the config could not be resolved (errors printed)
      def load_config
        result = PipelineBuilder.resolve_config(@options[:entry], PipelineBuilder::Context.from_options(@options))
        unless result.ok?
          result.errors.each { |message| log_error(message) }
          return false
        end

        @config = expand_variables(result.config, @options[:variables])
        @stages = result.stages
        @all_jobs = PipelineBuilder.job_definitions(@config)
        true
      end

      # Generate flat justfile (no dependencies)
      #
      # @return [String] Justfile content
      def generate_flat_justfile
        lines = []

        # Header
        lines << generate_header(flat: true)
        lines << ""

        # Variables section (if any)
        if @options[:variables].any?
          lines << "# Variables"
          @options[:variables].each do |key, value|
            lines << "export #{key} := \"#{escape_value(value)}\""
          end
          lines << ""
        end

        # Generate recipe for each job (alphabetically sorted)
        @all_jobs.keys.sort.each do |job_name|
          next if job_name.start_with?('.') # Skip template jobs
          job = @all_jobs[job_name]
          lines << format_recipe(job_name, job, dependencies: [])
          lines << ""
        end

        lines.join("\n")
      end

      # Generate graph justfile (with dependencies)
      #
      # @return [String] Justfile content
      def generate_graph_justfile
        lines = []

        # Header
        lines << generate_header(flat: false)
        lines << ""

        # Variables section
        if @options[:variables].any?
          lines << "# Variables"
          @options[:variables].each do |key, value|
            lines << "export #{key} := \"#{escape_value(value)}\""
          end
          lines << ""
        end

        # Generate recipes in topological order
        processed = Set.new
        @all_jobs.keys.sort.each do |job_name|
          next if job_name.start_with?('.') # Skip templates
          next if processed.include?(job_name)

          generate_recipe_with_deps(job_name, lines, processed)
        end

        lines.join("\n")
      end

      # Generate recipe with dependencies
      #
      # @param job_name [String] Job name
      # @param lines [Array<String>] Output lines
      # @param processed [Set] Already processed jobs
      def generate_recipe_with_deps(job_name, lines, processed)
        return if processed.include?(job_name)

        job = @all_jobs[job_name]
        return unless job

        # Get dependencies
        deps = resolve_job_dependencies(job_name)

        # Process dependencies first
        deps.each do |dep|
          generate_recipe_with_deps(dep, lines, processed)
        end

        # Generate this recipe
        lines << format_recipe(job_name, job, dependencies: deps)
        lines << ""

        processed.add(job_name)
      end

      # Resolve dependencies for a job
      #
      # @param job_name [String] Job name
      # @return [Array<String>] List of dependency job names
      def resolve_job_dependencies(job_name)
        job = @all_jobs[job_name]
        return [] unless job

        # Get explicit needs
        needs = extract_needs(job)
        return needs if needs.any?

        # No explicit needs - use stage-based dependencies
        job_stage = job['stage'] || job[:stage] || 'test'
        job_stage_index = @stages.index(job_stage)
        return [] unless job_stage_index && job_stage_index > 0

        # All jobs from previous stage
        previous_stage = @stages[job_stage_index - 1]
        @all_jobs.keys.select do |other_name|
          next if other_name.start_with?('.') # Skip templates
          other_job = @all_jobs[other_name]
          other_stage = other_job['stage'] || other_job[:stage] || 'test'
          other_stage == previous_stage
        end
      end

      # Extract needs from job configuration
      #
      # @param job [Hash] Job configuration
      # @return [Array<String>] List of job names
      def extract_needs(job)
        needs = job['needs'] || job[:needs]
        return [] if needs.nil? || needs.empty?

        if needs.is_a?(Array)
          needs.map do |need|
            case need
            when String
              need
            when Hash
              need['job'] || need[:job]
            else
              nil
            end
          end.compact
        else
          []
        end
      end

      # Format a job as a just recipe
      #
      # @param job_name [String] Job name
      # @param job [Hash] Job configuration
      # @param dependencies [Array<String>] Dependency job names
      # @return [String] Just recipe
      def format_recipe(job_name, job, dependencies: [])
        lines = []

        # Comment header with metadata
        stage = job['stage'] || job[:stage] || 'unknown'
        tags = job['tags'] || job[:tags] || []

        lines << "# #{job_name}"
        lines << "#   Stage: #{stage}"
        lines << "#   Tags: #{tags.empty? ? '(none)' : tags.join(', ')}" if tags.any?
        if dependencies.any?
          lines << "#   Depends: #{dependencies.join(', ')}"
        end

        # Recipe signature
        recipe_line = job_name.gsub(/[^a-zA-Z0-9_-]/, '_')
        if dependencies.any?
          recipe_line += ": #{dependencies.map { |d| d.gsub(/[^a-zA-Z0-9_-]/, '_') }.join(' ')}"
        else
          recipe_line += ":"
        end
        lines << recipe_line

        # Recipe body (combine before_script, script, after_script)
        script_lines = collect_script_lines(job)

        if script_lines.empty?
          lines << "    @echo 'No script defined for #{job_name}'"
        elsif script_lines.length == 1
          # Single line - simple format
          lines << "    #{escape_script_line(script_lines.first)}"
        else
          # Multiple lines - use indented format
          script_lines.each do |line|
            lines << "    #{escape_script_line(line)}"
          end
        end

        lines.join("\n")
      end

      # Collect all script lines for a job
      #
      # @param job [Hash] Job configuration
      # @return [Array<String>] Script lines
      def collect_script_lines(job)
        lines = []

        # before_script
        before_script = job['before_script'] || job[:before_script]
        if before_script
          lines.concat(Array(before_script))
        end

        # script
        script = job['script'] || job[:script]
        if script
          lines.concat(Array(script))
        end

        # after_script
        after_script = job['after_script'] || job[:after_script]
        if after_script
          lines.concat(Array(after_script))
        end

        lines
      end

      # Escape a script line for just syntax
      #
      # @param line [String] Script line
      # @return [String] Escaped line
      def escape_script_line(line)
        # Escape special characters for shell
        # Just uses sh/bash by default, so we need to handle:
        # - Backslashes
        # - Double quotes (just uses double quotes for strings)
        line = line.gsub('\\', '\\\\')
        line
      end

      # Escape a variable value
      #
      # @param value [String] Variable value
      # @return [String] Escaped value
      def escape_value(value)
        value.to_s.gsub('\\', '\\\\').gsub('"', '\\"')
      end

      # Generate file header
      #
      # @param flat [Boolean] Whether this is a flat justfile
      # @return [String] Header content
      def generate_header(flat:)
        mode = flat ? 'flat (no dependencies)' : 'with dependency graph'
        regenerate_cmd = if flat
                           "gitlab_ci_cli export-just --flat --output #{@options[:output] || 'justfile.gitlab.flat'}"
                         else
                           "gitlab_ci_cli export-just --graph --output #{@options[:output] || 'justfile.gitlab.graph'}"
                         end

        <<~HEADER.chomp
          # Auto-generated justfile from GitLab CI configuration (#{mode})
          # Source: #{@options[:entry]}
          # Generated: #{Time.now.iso8601}
          #
          # DO NOT EDIT - Regenerate with:
          #   #{regenerate_cmd}
          #
          # Usage:
          #   just --list                 # Show all available jobs
          #   just <job-name>             # Run a specific job
          #   just --dry-run <job-name>   # Show what would be executed
        HEADER
      end

      # Expand variables in configuration
      def expand_variables(obj, variables)
        case obj
        when Hash
          obj.transform_values { |v| expand_variables(v, variables) }
        when Array
          obj.map { |item| expand_variables(item, variables) }
        when String
          expanded = obj.dup
          variables.each do |key, value|
            value_str = value.to_s
            expanded = expanded.gsub(/\$\{#{Regexp.escape(key)}\}/) { value_str }
            expanded = expanded.gsub(/\$#{Regexp.escape(key)}\b/) { value_str }
          end
          expanded
        else
          obj
        end
      end

      # Log info message
      def log_info(message)
        puts message
      end

      # Log error message
      def log_error(message)
        $stderr.puts "Error: #{message}"
      end
    end
  end
end
