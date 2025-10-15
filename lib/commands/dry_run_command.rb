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

require_relative '../mock_server'
require_relative '../runner_fleet'
require_relative '../mock_runner'
require_relative '../mock_job'
require_relative '../include_processor'
require_relative '../extends_resolver'
require 'yaml'

module GitlabCiCli
  module Commands
    # DryRunCommand simulates pipeline execution against a runner fleet
    # without actually executing jobs. It provides a time-based simulation
    # showing job scheduling, runner assignments, and pipeline progression.
    #
    # MPED Principles Applied:
    # - Explicit state machine: Pipeline and job states are explicit and tracked
    # - No hidden mutations: All state changes are explicit and logged
    # - Clear loop termination: Max iterations prevent infinite loops
    # - Simple matching algorithm: Runner assignment is straightforward
    # - Fail-fast on errors: Invalid configurations are rejected immediately
    class DryRunCommand
      # Maximum simulation iterations to prevent infinite loops
      MAX_ITERATIONS = 10000

      # Simulation time step in seconds
      TIME_STEP_SECONDS = 1

      # Default job duration in simulation time (seconds)
      DEFAULT_JOB_DURATION = 5

      attr_reader :options, :server, :fleet

      # Initialize the dry-run command
      #
      # @param options [Hash] Command options
      # @option options [String] :entry Path to .gitlab-ci.yml file
      # @option options [String] :gitlab_dir Path to GitLab submodule
      # @option options [String] :runners Directory containing runner JSON files
      # @option options [String] :ref Git ref to simulate
      # @option options [Hash] :variables CI variables to set
      # @option options [Boolean] :verbose Enable verbose output
      def initialize(options = {})
        @options = validate_options(options)
        @server = nil
        @fleet = nil
      end

      # Execute the dry-run simulation
      #
      # @return [Integer] Exit code (0 for success, 1 for failure)
      def execute
        validate_prerequisites

        @server = MockServer.new(@options[:gitlab_dir])
        @fleet = load_runner_fleet

        pipeline = create_pipeline
        return 1 if pipeline.nil?

        run_simulation(pipeline)

        0
      rescue StandardError => e
        log_error("Dry-run failed: #{e.class.name}: #{e.message}")
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
          runners: options[:runners] || './runners',
          ref: options[:ref] || 'HEAD',
          variables: options[:variables] || {},
          verbose: options[:verbose] || false
        }
      end

      # Validate prerequisites before execution
      #
      # @raise [RuntimeError] If prerequisites are not met
      def validate_prerequisites
        unless File.exist?(@options[:entry])
          raise "CI config file not found: #{@options[:entry]}"
        end

        unless File.directory?(@options[:gitlab_dir])
          raise "GitLab directory not found: #{@options[:gitlab_dir]}"
        end

        unless File.directory?(@options[:runners])
          raise "Runners directory not found: #{@options[:runners]}"
        end
      end

      # Load runner fleet from directory
      #
      # @return [RunnerFleet] Loaded runner fleet
      def load_runner_fleet
        fleet = RunnerFleet.new
        runner_count = fleet.load_runners(@options[:runners])

        if runner_count == 0
          raise "No runners found in #{@options[:runners]}"
        else
          log_info("Loaded #{runner_count} runner(s)") if @options[:verbose]
        end

        fleet
      end

      # Create pipeline from configuration
      #
      # @return [Pipeline, nil] Created pipeline or nil on error
      def create_pipeline
        config_content = File.read(@options[:entry])

        # Parse YAML and process includes
        config = YAML.safe_load(config_content, permitted_classes: [Symbol], aliases: true)
        config = process_includes(config)
        config = resolve_extends(config)

        # Convert back to YAML for server
        processed_config_content = YAML.dump(config)

        # Display variables in verbose mode
        if @options[:verbose] && !@options[:variables].empty?
          log_info("Variables:")
          @options[:variables].each do |key, value|
            log_info("  #{key}=#{value}")
          end
          log_info("")
        end

        pipeline = @server.create_pipeline(
          processed_config_content,
          ref: @options[:ref],
          variables: @options[:variables]
        )

        log_info("Pipeline ##{pipeline.id} created with #{pipeline.jobs.count} job(s)")
        log_info("")

        pipeline
      rescue StandardError => e
        log_error("Failed to create pipeline: #{e.message}")
        nil
      end

      # Process include directives in the configuration
      #
      # @param config [Hash] Parsed YAML configuration
      # @return [Hash] Merged configuration with includes resolved
      def process_includes(config)
        return config unless config['include']

        # Get project path from entry file directory
        project_path = File.dirname(File.expand_path(@options[:entry]))

        # Get GitLab templates path if GitLab submodule exists
        gitlab_templates_path = nil
        if Dir.exist?(@options[:gitlab_dir])
          gitlab_templates_path = File.join(@options[:gitlab_dir], 'lib', 'gitlab', 'ci', 'templates')
        end

        # Create include processor
        processor = IncludeProcessor.new(
          project_path: project_path,
          gitlab_templates_path: gitlab_templates_path
        )

        # Process includes
        processor.process_includes(config)
      rescue IncludeDepthExceededError => e
        log_error("Include depth exceeded: #{e.depth} > #{e.max_depth}")
        raise
      rescue StandardError => e
        log_error("Error processing includes: #{e.message}")
        raise
      end

      # Resolve extends directives in the configuration
      #
      # @param config [Hash] Configuration with includes resolved
      # @return [Hash] Configuration with extends resolved
      def resolve_extends(config)
        resolver = ExtendsResolver.new
        resolver.resolve_extends(config)
      rescue StandardError => e
        log_error("Error resolving extends: #{e.message}")
        raise
      end

      # Run simulation loop
      #
      # @param pipeline [Pipeline] Pipeline to simulate
      def run_simulation(pipeline)
        simulation_time = 0
        iteration = 0

        # Track job start times and durations for simulation
        job_timers = {}
        # Track which runner is executing which job
        job_to_runner = {}

        while !pipeline_finished?(pipeline) && iteration < MAX_ITERATIONS
          # Process pipeline state transitions
          @server.process_pipeline(pipeline)

          # Process pending jobs - attempt to assign to runners
          pending_jobs = get_pending_jobs(pipeline)
          pending_jobs.each do |job|
            runner = assign_job_to_runner(job, simulation_time)
            job_to_runner[job.id] = runner if runner
          end

          # Process running jobs - check if they should complete
          running_jobs = get_running_jobs(pipeline)
          running_jobs.each do |job|
            # Initialize timer if not set
            job_timers[job.id] ||= { start: simulation_time, duration: DEFAULT_JOB_DURATION }

            # Check if job should complete
            timer = job_timers[job.id]
            if simulation_time >= timer[:start] + timer[:duration]
              complete_job(job, simulation_time)
              # Release runner capacity
              runner = job_to_runner[job.id]
              release_runner_for_job(job, runner)
            end
          end

          # Advance simulation time
          simulation_time += TIME_STEP_SECONDS
          iteration += 1
        end

        # Check for infinite loop condition
        if iteration >= MAX_ITERATIONS
          log_error("")
          log_error("Simulation terminated: Maximum iterations (#{MAX_ITERATIONS}) reached")
          log_error("This may indicate:")
          log_error("  - Circular dependencies in job needs")
          log_error("  - Jobs stuck in pending state (no eligible runners)")
          log_error("  - Jobs that never complete")
        end

        output_final_status(pipeline, simulation_time)
      end

      # Check if pipeline is finished
      #
      # @param pipeline [Pipeline] Pipeline to check
      # @return [Boolean] True if all jobs are finished
      def pipeline_finished?(pipeline)
        pipeline.jobs.all?(&:finished?)
      end

      # Get pending jobs from pipeline
      #
      # @param pipeline [Pipeline] Pipeline to query
      # @return [Array<MockJob>] List of pending jobs whose dependencies are satisfied
      def get_pending_jobs(pipeline)
        pipeline.jobs.select do |job|
          job.pending? && dependencies_satisfied?(job, pipeline)
        end
      end

      # Get running jobs from pipeline
      #
      # @param pipeline [Pipeline] Pipeline to query
      # @return [Array<MockJob>] List of running jobs
      def get_running_jobs(pipeline)
        pipeline.jobs.select(&:running?)
      end

      # Check if job dependencies are satisfied
      #
      # @param job [MockJob] Job to check
      # @param pipeline [Pipeline] Pipeline containing all jobs
      # @return [Boolean] True if all needed jobs are completed
      def dependencies_satisfied?(job, pipeline)
        return true if job.needs.empty?

        job.needs.all? do |needed_job_name|
          needed_job = pipeline.jobs.find { |j| j.name == needed_job_name }
          needed_job && needed_job.completed?
        end
      end

      # Assign job to an available runner
      #
      # @param job [MockJob] Job to assign
      # @param time [Integer] Current simulation time
      # @return [MockRunner, nil] Assigned runner or nil if no runner available
      def assign_job_to_runner(job, time)
        runner = @fleet.find_available_runner(job)

        if runner
          # Assign job to runner
          runner.assign_job(job)
          job.transition_to(MockJob::STATUS_RUNNING)

          log_info("[T+#{time}s] Job '#{job.name}' → Runner '#{runner.id}'")
          runner
        else
          log_warning("[T+#{time}s] Job '#{job.name}' waiting (no eligible runner)")
          nil
        end
      end

      # Complete a job
      #
      # @param job [MockJob] Job to complete
      # @param time [Integer] Current simulation time
      def complete_job(job, time)
        job.transition_to(MockJob::STATUS_COMPLETED)
        log_info("[T+#{time}s] Job '#{job.name}' completed")
      end

      # Release runner capacity for completed job
      #
      # @param job [MockJob] Completed job
      # @param runner [MockRunner] Runner that was executing the job
      # @raise [RuntimeError] If runner is nil (indicates state tracking error)
      def release_runner_for_job(job, runner)
        unless runner
          raise "Failed to release job '#{job.name}': no runner tracked for this job"
        end

        runner.release_job(job)
      end

      # Output final pipeline status
      #
      # @param pipeline [Pipeline] Completed pipeline
      # @param time [Integer] Final simulation time
      def output_final_status(pipeline, time)
        log_info("")
        log_info("Simulation completed at T+#{time}s")
        log_info("")

        # Calculate status
        all_completed = pipeline.jobs.all?(&:completed?)
        any_failed = pipeline.jobs.any?(&:failed?)
        any_pending = pipeline.jobs.any?(&:pending?)

        status = if all_completed
                   'success'
                 elsif any_failed
                   'failed'
                 elsif any_pending
                   'stuck'
                 else
                   'partial'
                 end

        log_info("Pipeline status: #{status}")

        # Job summary by status
        log_info("Job summary:")
        status_counts = Hash.new(0)
        pipeline.jobs.each { |job| status_counts[job.status] += 1 }

        status_counts.each do |job_status, count|
          log_info("  #{job_status}: #{count}")
        end
      end

      # Log info message
      #
      # @param message [String] Message to log
      def log_info(message)
        puts message
      end

      # Log warning message
      #
      # @param message [String] Warning message to log
      def log_warning(message)
        warn "Warning: #{message}"
      end

      # Log error message
      #
      # @param message [String] Error message to log
      def log_error(message)
        warn "Error: #{message}"
      end
    end
  end
end
