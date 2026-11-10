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
require_relative '../job_environment'
require_relative '../host_environment'
require_relative '../mock_pipeline'
require_relative '../shell_quote'

module GitlabCiCli
  module Commands
    # RunCommand executes a job on this host the way a GitLab Runner shell
    # executor would (JobEnvironment): the job's variables exported,
    # before_script + script in one bash with errexit/pipefail, after_script
    # in a second bash that also runs after a failure and sees
    # CI_JOB_STATUS, both in the project directory. Of this host's
    # environment both shells see only what --pass-env lets through
    # (HostEnvironment), under the job's variables.
    #
    # With --run-deps incl it first runs the jobs the target waits for,
    # scheduled by MockPipeline exactly as dry-run schedules them (`needs:`
    # for a DAG job, `needs: []` meaning none, earlier stages otherwise),
    # with real outcomes deciding `when: on_failure` / `always` jobs.
    #
    # Exit code: that of the first job that failed and was not allowed to;
    # 0 when there is none.
    class RunCommand
      attr_reader :options, :job_name

      # After SIGTERM, how long an after_script process group gets before
      # SIGKILL.
      KILL_GRACE_S = 5

      # Exit code reported for a shell killed by a signal (shell convention).
      SIGNAL_EXIT_BASE = 128

      # @param job_name [String] Name of the job to run
      # @param options [Hash] Command options
      # @option options [String] :entry Path to .gitlab-ci.yml file
      # @option options [String] :gitlab_dir Path to GitLab submodule
      # @option options [String] :run_deps 'incl' or 'excl' (include/exclude dependencies)
      # @option options [Hash] :variables CLI --variables
      # @option options [Array<String>, :all] :pass_env HostEnvironment mode (default [] = none)
      # @option options [Boolean] :verbose Enable verbose output
      def initialize(job_name, options = {})
        @job_name = job_name
        @options = validate_options(options)
      end

      # @return [Integer] exit code
      def execute
        context = PipelineBuilder::Context.from_options(@options)
        result = PipelineBuilder.build(@options[:entry], context)
        unless result.ok?
          result.errors.each { |message| log_error(message) }
          return 1
        end
        return 1 unless runnable?(result)

        pipeline = plan(result)
        log_info("Execution plan:")
        pipeline.jobs.each_with_index { |job, index| log_info("  #{index + 1}. #{job.name}") }
        log_info("")

        run_pipeline(pipeline) do |name|
          environment = JobEnvironment.build(result, name, cli_variables: context.variables,
                                                           project_dir: context.project_dir)
          execute_job(environment, result.pipeline_jobs.fetch(name))
        end
        report(pipeline)
      rescue JobEnvironment::Error => e
        log_error(e.message)
        1
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
          pass_env: options[:pass_env] || [],
          project: options[:project],
          pipeline: options[:pipeline],
          ref: options[:ref],
          verbose: options[:verbose] || false
        }
      end

      # Is @job_name a job of this pipeline? Says why not, otherwise.
      #
      # @param result [PipelineBuilder::Result] from build
      # @return [Boolean]
      def runnable?(result)
        if result.workflow_skipped
          log_error(PipelineBuilder::WORKFLOW_SKIPPED_MESSAGE)
          return false
        end
        if (job = result.pipeline_jobs[@job_name])
          return true unless job['script'].nil?

          log_error("Job '#{@job_name}' has no script (a trigger job): nothing to run locally")
          return false
        end

        if (reason = result.excluded_jobs[@job_name])
          log_error("Job '#{@job_name}' is excluded by rules in this pipeline context: #{reason}")
        elsif result.job_definitions.key?(@job_name)
          log_error("Job '#{@job_name}' is a hidden template and never runs")
        elsif !(instances = parallel_instances(result.job_definitions, @job_name)).empty?
          log_error("Job '#{@job_name}' is a parallel job; run one instance by its full name, e.g. " \
                    "run #{ShellQuote.quote(instances.first)}. Instances: #{instances.join(', ')}")
        else
          log_error("Job '#{@job_name}' not found in configuration")
        end
        log_error("Jobs in this pipeline: #{result.pipeline_jobs.keys.join(', ')}")
        false
      end

      # Names of the instances `base` expanded to (ParallelExpander), config
      # order: a job runs by its full name only, never all instances at once,
      # so `run` always runs what the user named. Matched by the names
      # upstream generates, not by CI_JOB_GROUP_NAME's suffix regex, which
      # also strips suffixes a user wrote.
      #
      # @return [Array<String>]
      def parallel_instances(job_definitions, base)
        job_definitions.filter_map do |name, job|
          index, total = PipelineBuilder.parallel_instance(job)
          next if index.nil?

          name if name == "#{base} #{index}/#{total}" || (name.start_with?("#{base}: [") && name.end_with?(']'))
        end
      end

      # The jobs to run, as a pipeline of their own, in stage order (config
      # order within a stage).
      #
      # excl: the target alone, run regardless of its `needs:` and `when:`:
      # it was asked for, and there is nothing before it to wait for.
      # incl: the target and every job it transitively waits for. That set
      # is closed under MockPipeline#previous_jobs, so each job waits for
      # the same jobs it waits for in the whole pipeline.
      #
      # @return [MockPipeline]
      def plan(result)
        stages = result.stages
        jobs = if @options[:run_deps] == 'incl'
                 whole = MockPipeline.new(id: 1, stages: stages, jobs: result.pipeline_jobs, ref: nil, variables: {})
                 names = waited_for(whole, @job_name)
                 result.pipeline_jobs.select { |name, _| names.include?(name) }
               else
                 { @job_name => result.pipeline_jobs.fetch(@job_name).except('needs', 'when') }
               end
        by_stage = jobs.sort_by.with_index { |(_, job), index| [stages.index(job['stage'] || PipelineBuilder::DEFAULT_JOB_STAGE), index] }
        MockPipeline.new(id: 1, stages: stages, jobs: by_stage.to_h, ref: nil, variables: {})
      end

      # `name` and every job it transitively waits for. Bounded: each job is
      # visited once.
      #
      # @return [Array<String>]
      def waited_for(pipeline, name)
        seen = [name]
        queue = [name]
        until queue.empty?
          pipeline.previous_jobs(pipeline.find_job(queue.shift)).each do |job|
            next if seen.include?(job.name)

            seen << job.name
            queue << job.name
          end
        end
        seen
      end

      # Run pending jobs as MockPipeline lets them start, one at a time;
      # skip those whose `when:` rejects their previous jobs' outcome.
      # Bounded: every pass starts one job or ends the loop.
      #
      # @yieldparam name [String] job to execute
      # @yieldreturn [Integer] its exit code
      def run_pipeline(pipeline)
        (pipeline.jobs.size + 1).times do
          pipeline.skip_blocked_jobs.each do |job|
            log_info("Job '#{job.name}' skipped: when: #{job.when_to_run} and the jobs before it ended #{pipeline.previous_status(job)}")
          end
          job = pipeline.pending_jobs.first
          return if job.nil?

          job.transition_to(MockJob::STATUS_RUNNING)
          job.finish(yield(job.name))
        end
        raise "run_pipeline: jobs still pending after #{pipeline.jobs.size + 1} passes"
      end

      # @return [Integer] first not-allowed failure's exit code, else 0
      def report(pipeline)
        unfinished = pipeline.jobs.reject(&:finished?)
        raise "jobs left unfinished: #{unfinished.map(&:name).join(', ')}" unless unfinished.empty?

        log_info("")
        log_info("Summary:")
        pipeline.jobs.each { |job| log_info("  #{job.name}: #{outcome(job)}") }
        failed = pipeline.jobs.find { |job| job.failed? && !job.allow_failure }
        failed ? failed.exit_code : 0
      end

      def outcome(job)
        return 'skipped' if job.skipped?
        return 'success' if job.completed?
        return "failed (exit code #{job.exit_code}, allowed to fail)" if job.allow_failure

        "failed (exit code #{job.exit_code})"
      end

      # One job: main shell, then after_script shell. A job without script
      # (trigger job) can only be a dependency here (runnable? refuses it
      # as the target): it is reported, not run, and counts as success.
      #
      # @param environment [JobEnvironment::Job]
      # @param job [Hash] the job's config, for display only
      # @return [Integer] the main script's exit code
      def execute_job(environment, job)
        log_info("=" * 80)
        log_info("Running job: #{environment.name}")
        log_info("=" * 80)
        environment.warnings.each { |warning| log_warning(warning) }
        if job['script'].nil?
          log_info("No script (a trigger job): not run locally, counted as success")
          return 0
        end
        log_info("Image #{job['image'].inspect} is not used: the job runs on this host") if job['image'] && @options[:verbose]
        log_info(environment.main_script) if @options[:verbose]

        exit_code = run_shell(environment.variables, environment.main_script, environment.project_dir)
        run_after_script(environment, exit_code) if environment.after_script

        log_info("")
        if exit_code.zero?
          log_info("Job '#{environment.name}' succeeded")
        else
          log_error("Job '#{environment.name}' failed with exit code #{exit_code}")
        end
        exit_code
      end

      # Upstream: after_script errors and its timeout are reported and do
      # not change the job's result (AFTER_SCRIPT_IGNORE_ERRORS defaults to
      # true, common/consts.go DefaultAfterScriptIgnoreErrors).
      def run_after_script(environment, main_exit_code)
        status = main_exit_code.zero? ? 'success' : 'failed'
        log_info("Running after script...")
        exit_code = run_shell(environment.after_script_variables(status), environment.after_script,
                              environment.project_dir, timeout_s: environment.after_script_timeout_s)
        if exit_code == :timeout
          log_warning("after_script timed out after #{environment.after_script_timeout_s}s and was killed; the job result is unchanged")
        elsif !exit_code.zero?
          log_warning("after_script failed with exit code #{exit_code}; the job result is unchanged")
        end
      end

      # bash -c SHELL_PRELUDE + script, stdin empty (runner: `: | eval`),
      # stdout/stderr inherited. Its environment is exactly the host
      # variables --pass-env selects with the job's variables over them
      # (unsetenv_others: nothing else of this process's environment).
      #
      # With a timeout the shell gets its own process group, so everything
      # it started is killed with it.
      #
      # @return [Integer, :timeout]
      def run_shell(variables, script, project_dir, timeout_s: nil)
        $stdout.flush
        $stderr.flush
        spawn_options = { chdir: project_dir, in: File::NULL }
        spawn_options[:pgroup] = true if timeout_s
        environment = HostEnvironment.select(ENV.to_h, @options[:pass_env]).merge(variables)
        pid = Process.spawn(environment, 'bash', '-c', JobEnvironment::SHELL_PRELUDE + script,
                            unsetenv_others: true, **spawn_options)
        waiter = Process.detach(pid)
        return exit_code_of(waiter.value) if timeout_s.nil?

        begin
          return exit_code_of(waiter.value) if waiter.join(timeout_s)

          kill_group(pid, waiter)
          :timeout
        ensure
          kill_group(pid, waiter) if waiter.alive?
        end
      end

      def kill_group(pid, waiter)
        Process.kill('TERM', -pid)
        Process.kill('KILL', -pid) unless waiter.join(KILL_GRACE_S)
        waiter.join
      rescue Errno::ESRCH
        nil # already gone
      end

      def exit_code_of(status)
        status.exitstatus || (SIGNAL_EXIT_BASE + status.termsig)
      end

      def log_info(message)
        puts message
      end

      def log_warning(message)
        $stderr.puts "Warning: #{message}"
      end

      def log_error(message)
        $stderr.puts "Error: #{message}"
      end
    end
  end
end
