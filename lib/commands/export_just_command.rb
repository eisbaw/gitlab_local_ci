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
require_relative '../mock_pipeline'
require 'time'

module GitlabCiCli
  module Commands
    # ExportJustCommand writes the pipeline's jobs as justfile recipes, each
    # behaving like `run <job>` (both read JobEnvironment):
    #
    # - a shebang recipe (one bash for the whole body), so `cd`, exported
    #   variables and multi-line `- |` entries keep their meaning;
    # - the job's variables exported, values as of the export (CI_COMMIT_SHA
    #   and friends are a snapshot: regenerate after committing);
    # - cwd = the project directory, an absolute path (regenerate if the
    #   checkout moves);
    # - before_script + script in their own `bash -c` with the runner's
    #   errexit/pipefail prelude, stdin empty;
    # - after_script in a second `bash -c` that also runs after a failure,
    #   with CI_JOB_STATUS=success|failed, under `timeout <after_script_timeout_s>` when coreutils
    #   `timeout` exists; its failure is reported and does not change the
    #   recipe's exit code, which is the script's.
    #
    # Graph mode: a recipe depends on the jobs MockPipeline says it waits for
    # (its `needs:`, `needs: []` meaning none, else every earlier-stage job),
    # except `when: on_failure` jobs. just runs dependencies and stops at the
    # first failure, so a recipe is the success path: on_failure jobs never
    # run there, `always` and `manual` jobs do (as in dry-run and run).
    class ExportJustCommand
      attr_reader :options

      # Quoted heredoc delimiter the job scripts are embedded with. A script
      # line equal to it would end the heredoc early, so that is an error.
      SCRIPT_DELIMITER = 'GITLAB_CI_CLI_SCRIPT_EOF'

      # @param options [Hash] Command options
      # @option options [String] :entry Path to .gitlab-ci.yml file
      # @option options [String] :gitlab_dir Path to GitLab submodule
      # @option options [String] :output Output filename
      # @option options [Boolean] :flat Generate flat list (no dependencies)
      # @option options [Boolean] :graph Generate with dependencies
      # @option options [Hash] :variables CLI --variables
      # @option options [Boolean] :verbose Enable verbose output
      def initialize(options = {})
        @options = validate_options(options)
      end

      # @return [Integer] Exit code (0 for success, 1 for failure)
      def execute
        context = PipelineBuilder::Context.from_options(@options)
        result = PipelineBuilder.build(@options[:entry], context)
        unless result.ok?
          result.errors.each { |message| log_error(message) }
          return 1
        end
        if result.workflow_skipped
          log_error(PipelineBuilder::WORKFLOW_SKIPPED_MESSAGE)
          return 1
        end

        output = justfile(result, context)
        if @options[:output]
          File.write(@options[:output], output)
          log_info("Exported justfile to: #{@options[:output]}")
        else
          puts output
        end
        0
      rescue JobEnvironment::Error => e
        log_error(e.message)
        1
      rescue StandardError => e
        log_error("Export failed: #{e.message}")
        log_error("Backtrace: #{e.backtrace.first(5).join("\n")}") if @options[:verbose]
        1
      end

      private

      def validate_options(options)
        {
          entry: options[:entry] || './.gitlab-ci.yml',
          gitlab_dir: options[:gitlab_dir] || './gitlab',
          output: options[:output],
          flat: options[:flat] || false,
          graph: options[:graph] || false,
          variables: options[:variables] || {},
          project: options[:project],
          pipeline: options[:pipeline],
          ref: options[:ref],
          verbose: options[:verbose] || false
        }
      end

      # @return [String] justfile content
      def justfile(result, context)
        jobs = result.pipeline_jobs
        recipe_names = recipe_names(jobs.keys)
        dependencies = @options[:flat] ? {} : dependencies(result)
        names = @options[:flat] ? jobs.keys.sort : jobs.keys

        recipes = names.map do |name|
          environment = JobEnvironment.build(result, name, cli_variables: context.variables,
                                                           project_dir: context.project_dir)
          environment.warnings.each { |warning| log_warning("#{name}: #{warning}") }
          format_recipe(environment, jobs.fetch(name), recipe_names,
                        dependencies.fetch(name, []))
        end
        [generate_header, *recipes].join("\n\n") + "\n"
      end

      # job name => recipe name: just identifiers are [A-Za-z_][A-Za-z0-9_-]*.
      #
      # @raise [RuntimeError] when two jobs map to one recipe name
      def recipe_names(job_names)
        names = job_names.to_h do |name|
          recipe = name.gsub(/[^a-zA-Z0-9_-]/, '_')
          recipe = "_#{recipe}" unless recipe.match?(/\A[A-Za-z_]/)
          [name, recipe]
        end
        clash = names.group_by { |_, recipe| recipe }.find { |_, pairs| pairs.size > 1 }
        raise "jobs #{clash[1].map(&:first).map(&:inspect).join(' and ')} would both be recipe '#{clash[0]}'" if clash

        names
      end

      # name => names of the jobs its recipe depends on (class comment).
      def dependencies(result)
        pipeline = MockPipeline.new(id: 1, stages: result.stages, jobs: result.pipeline_jobs, ref: nil, variables: {})
        pipeline.jobs.to_h do |job|
          previous = pipeline.previous_jobs(job).reject { |other| other.when_to_run == 'on_failure' }
          [job.name, previous.map(&:name)]
        end
      end

      # @param environment [JobEnvironment::Job]
      # @param job [Hash] job config (stage, tags, script presence)
      def format_recipe(environment, job, recipe_names, dependencies)
        lines = ["# #{environment.name}", "#   Stage: #{job['stage'] || PipelineBuilder::DEFAULT_JOB_STAGE}"]
        tags = Array(job['tags'])
        lines << "#   Tags: #{tags.join(', ')}" unless tags.empty?
        lines << "#   Depends: #{dependencies.join(', ')}" unless dependencies.empty?
        signature = [recipe_names.fetch(environment.name), *dependencies.map { |name| recipe_names.fetch(name) }]
        lines << "#{signature.first}:#{signature.drop(1).map { |name| " #{name}" }.join}"
        body = job['script'].nil? ? trigger_body(environment) : recipe_body(environment)
        # Split again: a value or script entry may span lines, and each
        # justfile line needs the indentation.
        body_lines = body.flat_map { |line| line.split("\n", -1) }
        lines.concat(body_lines.map { |line| line.empty? ? '' : "    #{line.gsub('{{', '{{{{')}" })
        lines.join("\n")
      end

      def trigger_body(environment)
        ['#!/usr/bin/env bash', "echo #{shell_quote("#{environment.name}: no script (a trigger job), nothing to run locally")}"]
      end

      # The recipe's bash program (class comment). Every line goes into the
      # justfile indented; just strips that indentation, so lines of a
      # multi-line entry keep their own.
      #
      # @return [Array<String>]
      def recipe_body(environment)
        body = ['#!/usr/bin/env bash']
        body.concat(environment.variables.map { |key, value| "export #{key}=#{shell_quote(value)}" })
        body << "cd #{shell_quote(environment.project_dir)} || exit"
        body.concat(embedded_script('gitlab_ci_main_script', environment.main_script))
        body << 'bash -c "$gitlab_ci_main_script" </dev/null'
        body << 'gitlab_ci_exit_code=$?'
        if environment.after_script
          body << 'if [ "$gitlab_ci_exit_code" -eq 0 ]; then export CI_JOB_STATUS=success; else export CI_JOB_STATUS=failed; fi'
          body.concat(embedded_script('gitlab_ci_after_script', environment.after_script))
          body << 'gitlab_ci_timeout=(); if command -v timeout >/dev/null; then ' \
                  "gitlab_ci_timeout=(timeout #{environment.after_script_timeout_s}); fi"
          body << '"${gitlab_ci_timeout[@]}" bash -c "$gitlab_ci_after_script" </dev/null ||' \
                  ' echo "after_script failed or timed out (exit code $?); the job result is unchanged" >&2'
        end
        body << 'exit "$gitlab_ci_exit_code"'
      end

      # `variable` := SHELL_PRELUDE + script, verbatim (quoted heredoc: no
      # expansion, backslashes kept).
      def embedded_script(variable, script)
        text = JobEnvironment::SHELL_PRELUDE + script
        if text.lines.any? { |line| line.chomp == SCRIPT_DELIMITER }
          raise "a script line is exactly #{SCRIPT_DELIMITER}, which ends the embedded script"
        end

        ["IFS= read -r -d '' #{variable} <<'#{SCRIPT_DELIMITER}'", text, SCRIPT_DELIMITER]
      end

      # Single-quoted for bash: nothing inside is expanded.
      def shell_quote(value)
        "'#{value.gsub("'") { %q('\\'') }}'"
      end

      def generate_header
        mode = @options[:flat] ? 'flat (no dependencies)' : 'with dependency graph'
        flag = @options[:flat] ? '--flat' : '--graph'
        default_output = @options[:flat] ? 'justfile.gitlab.flat' : 'justfile.gitlab.graph'

        <<~HEADER.chomp
          # Auto-generated justfile from GitLab CI configuration (#{mode})
          # Source: #{@options[:entry]}
          # Generated: #{Time.now.iso8601}
          #
          # DO NOT EDIT - Regenerate with:
          #   gitlab_ci_cli export-just #{flag} --output #{@options[:output] || default_output}
          #
          # Each recipe runs its job like `gitlab_ci_cli run`: the job's variables
          # (as of this export) exported, cwd = the project directory,
          # before_script + script in one bash with errexit and pipefail,
          # after_script in a second bash with CI_JOB_STATUS, also after a failure.
          #
          # Usage:
          #   just --list                 # Show all available jobs
          #   just <job-name>             # Run a specific job
          #   just --dry-run <job-name>   # Show what would be executed
        HEADER
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
