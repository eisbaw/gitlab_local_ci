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
require_relative '../pipeline_builder'

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
      # Bound on simulated ticks (TIME_STEP_SECONDS each). Only a pipeline
      # still making progress reaches it (~2000 sequential 5 s jobs); a
      # stuck one stops as soon as no state can change.
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

        context = PipelineBuilder::Context.from_options(@options)
        @server = MockServer.new(
          project_dir: context.project_dir,
          pipeline_source: context.pipeline_source
        )
        @fleet = load_runner_fleet

        pipeline = create_pipeline(context)
        return 1 if pipeline.nil?

        run_simulation(pipeline)
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
          verbose: options[:verbose] || false,
          project: options[:project],
          pipeline: options[:pipeline] || 'push'
        }
      end

      # Validate prerequisites before execution
      #
      # @raise [RuntimeError] If prerequisites are not met
      def validate_prerequisites
        unless File.exist?(@options[:entry])
          raise "CI config file not found: #{@options[:entry]}"
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
      # @param context [PipelineBuilder::Context]
      # @return [Pipeline, nil] Created pipeline or nil on error
      def create_pipeline(context)
        result = PipelineBuilder.build(@options[:entry], context)
        unless result.ok?
          result.errors.each { |message| log_error(message) }
          return nil
        end
        if result.workflow_skipped
          log_info(PipelineBuilder::WORKFLOW_SKIPPED_MESSAGE)
          return nil
        end

        # Display variables in verbose mode
        if @options[:verbose] && !@options[:variables].empty?
          log_info("Variables:")
          @options[:variables].each do |key, value|
            log_info("  #{key}=#{value}")
          end
          log_info("")
        end

        pipeline = @server.create_pipeline_from(
          stages: result.stages,
          jobs: expand_variables(result.pipeline_jobs, @options[:variables]),
          ref: @options[:ref],
          variables: @options[:variables]
        )

        log_info("Pipeline ##{pipeline.id} created with #{pipeline.jobs.count} job(s)")
        log_info("")

        pipeline
      rescue MockServer::ConfigurationError => e
        log_error("Failed to create pipeline: #{e.message}")
        nil
      end

      # Extract job name from key_path for error messages
      #
      # @param key_path [Array] Path of keys (e.g., ["job_name", "tags"])
      # @return [String] Job name or "unknown"
      def extract_job_name_from_path(key_path)
        # The job name is typically the first element in the path
        # (e.g., ["test_job", "tags"] -> "test_job")
        return "unknown" if key_path.empty?
        key_path.first.to_s
      end

      # Recursively expand variables in configuration
      #
      # @param obj [Object] Configuration object (Hash, Array, String, etc.)
      # @param variables [Hash] Variable substitutions
      # @param key_path [Array] Path of keys leading to current object (for context)
      # @return [Object] Configuration with variables expanded
      def expand_variables(obj, variables, key_path = [])
        case obj
        when Hash
          result = {}
          obj.each do |key, value|
            # Do not substitute into rule expressions: `if:` strings under
            # a `rules:` array are evaluated by RulesEvaluator with proper
            # $VAR lookup. Textual gsub would corrupt them (e.g. turning
            # `$SUBMODULE_UPDATE == "true"` into `true == "true"`).
            key_str = key.to_s
            if key_str == 'if' && key_path.last.to_s == 'rules'
              result[key] = value
            else
              result[key] = expand_variables(value, variables, key_path + [key])
            end
          end
          result
        when Array
          expanded_items = obj.map { |item| expand_variables(item, variables, key_path) }

          # Only filter unexpanded variables from 'tags' arrays
          # This is a workaround for jobs that use dynamic variables (e.g., ${RUNNER})
          # which are not available during dry-run simulation
          if key_path.last == 'tags' || key_path.last == :tags
            filtered = []
            expanded_items.each do |item|
              if item.is_a?(String) && item.match?(/\$\{[^}]+\}|\$[A-Z_][A-Z0-9_]*/)
                # Log warning about filtered unexpanded variable
                job_name = extract_job_name_from_path(key_path)
                log_warning("Filtered unexpanded variable from tags in job '#{job_name}': #{item}") if @options[:verbose]
              else
                filtered << item
              end
            end
            filtered
          else
            expanded_items
          end
        when String
          # Expand ${VAR} and $VAR syntax
          # Use block form to avoid backreference issues with replacement string
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

      # Run the simulation until every job is finished, nothing can change
      # any more (stuck), or MAX_ITERATIONS ticks.
      #
      # @param pipeline [MockPipeline] Pipeline to simulate
      # @return [Integer] exit code: 0 success, 1 stuck/failed/gave up
      def run_simulation(pipeline)
        simulation_time = 0
        job_timers = {}    # job id => { start:, duration: }
        job_to_runner = {} # job id => MockRunner running it
        reported_wait = {} # job name => last reported wait reason
        outcome = :max_iterations

        MAX_ITERATIONS.times do
          if pipeline_finished?(pipeline)
            outcome = :finished
            break
          end

          @server.process_pipeline(pipeline)

          skipped = pipeline.skip_blocked_jobs
          skipped.each do |job|
            log_info("[T+#{simulation_time}s] Job '#{job.name}' skipped (when: #{job.when_to_run}, previous jobs: #{pipeline.previous_status(job)})")
          end

          pipeline.pending_jobs.each do |job|
            runner = assign_job_to_runner(job, simulation_time, reported_wait)
            job_to_runner[job.id] = runner if runner
          end

          running_jobs = get_running_jobs(pipeline)
          # Job states only change by a skip or a running job finishing, and
          # runner capacity only frees when one does. With neither, every
          # later tick would be this one again.
          if running_jobs.empty? && skipped.empty?
            outcome = :stuck
            break
          end

          running_jobs.each do |job|
            job_timers[job.id] ||= { start: simulation_time, duration: DEFAULT_JOB_DURATION }
            timer = job_timers[job.id]
            next unless simulation_time >= timer[:start] + timer[:duration]

            complete_job(job, simulation_time)
            release_runner_for_job(job, job_to_runner[job.id])
          end

          simulation_time += TIME_STEP_SECONDS
        end

        output_final_status(pipeline, simulation_time, outcome)
      end

      # Check if pipeline is finished
      #
      # @param pipeline [Pipeline] Pipeline to check
      # @return [Boolean] True if all jobs are finished
      def pipeline_finished?(pipeline)
        pipeline.jobs.all?(&:finished?)
      end

      # Get running jobs from pipeline
      #
      # @param pipeline [Pipeline] Pipeline to query
      # @return [Array<MockJob>] List of running jobs
      def get_running_jobs(pipeline)
        pipeline.jobs.select(&:running?)
      end

      # Assign a ready job to a free runner, or report once per job and
      # reason why it waits: no runner can ever take it (a warning, the
      # pipeline will be stuck) or every runner that can is busy (normal
      # queueing, a timeline line).
      #
      # @param job [MockJob] Job to assign
      # @param time [Integer] Current simulation time
      # @param reported_wait [Hash] job name => last reported reason; updated
      # @return [MockRunner, nil] Assigned runner or nil if no runner available
      def assign_job_to_runner(job, time, reported_wait)
        runner = @fleet.find_available_runner(job)

        if runner
          runner.assign_job(job)
          job.transition_to(MockJob::STATUS_RUNNING)

          log_info("[T+#{time}s] Job '#{job.name}' → Runner '#{runner.id}'")
          return runner
        end

        reason = @fleet.eligible_runners(job).empty? ? :no_runner : :busy
        return nil if reported_wait[job.name] == reason

        reported_wait[job.name] = reason
        if reason == :no_runner
          log_warning("[T+#{time}s] Job '#{job.name}' cannot start: #{no_runner_reason(job)}")
        else
          log_info("[T+#{time}s] Job '#{job.name}' queued: every runner that can take it is busy")
        end
        log_runner_compatibility(job) if @options[:verbose]
        nil
      end

      # Why no runner in the fleet can ever take the job.
      #
      # @param job [MockJob] job with no eligible runner
      # @return [String]
      def no_runner_reason(job)
        tags = job.tag_list || []
        if tags.empty?
          'it has no tags and no runner has run_untagged: true'
        else
          "no runner has tags [#{tags.join(', ')}]"
        end
      end

      # Verbose: job tags against every runner.
      #
      # @param job [MockJob]
      def log_runner_compatibility(job)
        log_info("  Job tags: #{(job.tag_list || []).inspect}")
        log_info("  Available runners:")
        @fleet.runners.each do |r|
          log_info("    - #{r.id}: tags=#{r.tags.inspect}, can_handle=#{r.can_handle?(job)}, has_capacity=#{r.has_capacity?}")
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

      # Previous jobs listed per stuck job before "and N more".
      STUCK_WAITS_FOR_MAX = 5

      # Output final pipeline status and pick the exit code.
      #
      # @param pipeline [MockPipeline]
      # @param time [Integer] Final simulation time
      # @param outcome [Symbol] :finished, :stuck or :max_iterations
      # @return [Integer] exit code
      def output_final_status(pipeline, time, outcome)
        log_info("")
        log_info("Simulation #{outcome == :finished ? 'completed' : 'stopped'} at T+#{time}s")
        log_info("")

        status = outcome == :finished ? pipeline.status : 'stuck'
        log_info("Pipeline status: #{status}")

        log_info("Job summary:")
        status_counts = Hash.new(0)
        pipeline.jobs.each { |job| status_counts[job.status] += 1 }
        status_counts.each do |job_status, count|
          log_info("  #{job_status}: #{count}")
        end

        case outcome
        when :finished
          [MockPipeline::STATE_FAILED, :canceled].include?(status) ? 1 : 0
        when :stuck
          report_stuck_jobs(pipeline, time)
          1
        else
          log_error("Simulation gave up after #{MAX_ITERATIONS} simulated seconds with jobs still running or queued")
          1
        end
      end

      # One line per job that can never start, with the reason.
      #
      # @param pipeline [MockPipeline] stuck: no job running, none can start
      # @param time [Integer]
      def report_stuck_jobs(pipeline, time)
        stuck_jobs = pipeline.jobs.select(&:pending?)
        ready = pipeline.pending_jobs
        log_error("Pipeline stuck at T+#{time}s: #{stuck_jobs.size} job(s) can never start")
        stuck_jobs.each do |job|
          reason = if ready.include?(job)
                     # Nothing runs, so every runner is free: a ready job
                     # left pending has no eligible runner, or capacity leaked.
                     unless @fleet.eligible_runners(job).empty?
                       raise "invariant: '#{job.name}' is ready, nothing runs, yet eligible runners exist (capacity leak?)"
                     end
                     no_runner_reason(job)
                   else
                     waits_for = pipeline.previous_jobs(job).reject(&:finished?).map(&:name)
                     more = waits_for.size > STUCK_WAITS_FOR_MAX ? ", and #{waits_for.size - STUCK_WAITS_FOR_MAX} more" : ''
                     "waits for #{waits_for.first(STUCK_WAITS_FOR_MAX).join(', ')}#{more}"
                   end
          log_error("  - #{job.name}: #{reason}")
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
