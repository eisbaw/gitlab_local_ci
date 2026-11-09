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
require 'open3'

module GitlabCiCli
  module Commands
    # RunCommand executes a specific job locally
    # Optionally includes dependencies in topologically sorted order
    #
    # MPED Principles Applied:
    # - Fail-fast: Validates job exists and dependencies are acyclic
    # - Explicit: Clear execution order and output
    # - Simple: Straightforward script execution
    class RunCommand
      attr_reader :options, :job_name

      # Initialize the run command
      #
      # @param job_name [String] Name of the job to run
      # @param options [Hash] Command options
      # @option options [String] :entry Path to .gitlab-ci.yml file
      # @option options [String] :gitlab_dir Path to GitLab submodule
      # @option options [String] :run_deps 'incl' or 'excl' (include/exclude dependencies)
      # @option options [Hash] :variables CI variables to set
      # @option options [Boolean] :verbose Enable verbose output
      def initialize(job_name, options = {})
        @job_name = job_name
        @options = validate_options(options)
        @config = nil
        @all_jobs = nil
      end

      # Execute the run command
      #
      # @return [Integer] Exit code (0 for success, 1 for failure)
      def execute
        return 1 unless load_config

        # Validate job exists
        unless @all_jobs.key?(@job_name)
          log_error("Job '#{@job_name}' not found in configuration")
          available_jobs = @all_jobs.keys.reject { |j| j.start_with?('.') }
          log_error("Available jobs: #{available_jobs.join(', ')}")
          return 1
        end

        # Determine which jobs to run
        jobs_to_run = if @options[:run_deps] == 'incl'
                        resolve_dependencies(@job_name)
                      else
                        [@job_name]
                      end

        log_info("Execution plan:")
        jobs_to_run.each_with_index do |job, idx|
          log_info("  #{idx + 1}. #{job}")
        end
        log_info("")

        # Execute jobs in order
        jobs_to_run.each do |job|
          success = execute_job(job)
          return 1 unless success
        end

        log_info("")
        log_info("All jobs completed successfully")
        0
      rescue StandardError => e
        log_error("Execution failed: #{e.message}")
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
          run_deps: options[:run_deps] || 'excl',
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
        @all_jobs = PipelineBuilder.job_definitions(@config)
        true
      end

      # Recursively expand variables in configuration
      #
      # @param obj [Object] Configuration object
      # @param variables [Hash] Variable substitutions
      # @return [Object] Configuration with variables expanded
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

      # Resolve job dependencies using topological sort
      #
      # @param job_name [String] Name of the job
      # @return [Array<String>] Ordered list of jobs (dependencies first)
      def resolve_dependencies(job_name)
        stages = @config['stages'] || %w[build test deploy]
        visited = {}
        result = []

        # Recursive DFS to build dependency order
        visit = lambda do |name|
          return if visited[name]

          job = @all_jobs[name]
          return unless job # Skip if job doesn't exist

          visited[name] = :visiting

          # Add explicit 'needs' dependencies
          needs = extract_needs(job)
          needs.each do |dep|
            if visited[dep] == :visiting
              raise "Circular dependency detected: #{name} -> #{dep}"
            end
            visit.call(dep)
          end

          # Add implicit stage dependencies if no explicit needs
          if needs.empty?
            job_stage = job['stage'] || job[:stage] || 'test'
            job_stage_index = stages.index(job_stage)

            if job_stage_index && job_stage_index > 0
              # All jobs in previous stages are dependencies
              previous_stages = stages[0...job_stage_index]
              @all_jobs.each do |other_name, other_job|
                next if other_name.start_with?('.') # Skip templates
                other_stage = other_job['stage'] || other_job[:stage] || 'test'
                if previous_stages.include?(other_stage)
                  if visited[other_name] == :visiting
                    raise "Circular dependency detected: #{name} -> #{other_name}"
                  end
                  visit.call(other_name)
                end
              end
            end
          end

          visited[name] = :visited
          result << name
        end

        visit.call(job_name)
        result
      end

      # Extract needs from job configuration
      #
      # @param job [Hash] Job configuration
      # @return [Array<String>] List of job names this job depends on
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

      # Execute a single job
      #
      # @param job_name [String] Name of the job to execute
      # @return [Boolean] True if job succeeded
      def execute_job(job_name)
        job = @all_jobs[job_name]

        log_info("=" * 80)
        log_info("Running job: #{job_name}")
        log_info("=" * 80)

        # Build script to execute
        script_lines = []

        # Add before_script
        before_script = job['before_script'] || job[:before_script]
        if before_script
          script_lines.concat(Array(before_script))
        end

        # Add main script
        script = job['script'] || job[:script]
        unless script
          log_error("Job '#{job_name}' has no script to execute")
          return false
        end
        script_lines.concat(Array(script))

        # Add after_script
        after_script = job['after_script'] || job[:after_script]
        if after_script
          script_lines.concat(Array(after_script))
        end

        # Execute script
        full_script = script_lines.join("\n")

        log_info("") if @options[:verbose]
        log_info("Script:") if @options[:verbose]
        log_info(full_script) if @options[:verbose]
        log_info("") if @options[:verbose]

        success = execute_script(full_script)

        if success
          log_info("")
          log_info("Job '#{job_name}' completed successfully")
          log_info("")
        else
          log_error("")
          log_error("Job '#{job_name}' failed")
          log_error("")
        end

        success
      end

      # Execute a shell script
      #
      # @param script [String] Shell script to execute
      # @return [Boolean] True if script succeeded (exit code 0)
      def execute_script(script)
        # Use Open3.popen3 to capture output in real-time
        # Use 'bash' from PATH instead of hardcoded /bin/bash for nix compatibility
        Open3.popen3('bash', '-e') do |stdin, stdout, stderr, wait_thr|
          stdin.write(script)
          stdin.close

          # Read stdout and stderr simultaneously
          threads = []
          threads << Thread.new do
            stdout.each_line do |line|
              puts line
            end
          end

          threads << Thread.new do
            stderr.each_line do |line|
              $stderr.puts line
            end
          end

          threads.each(&:join)

          exit_status = wait_thr.value
          exit_status.success?
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
