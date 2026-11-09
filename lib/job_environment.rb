# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'tsort'
require_relative 'pipeline_builder'

# What one job's shell sees: its variables, as the runner exports them, and
# its script phases. The one place `run` and `export-just` get both from,
# so a recipe and a local run cannot disagree about a job.
#
# Pure: everything comes from a PipelineBuilder::Result (built by `build`)
# and the CLI variables; no I/O.
#
# Variables, in the order upstream appends them (a later one with the same
# key wins, doc/ci/variables/_index.md "CI/CD variable precedence"):
#
#   job predefined   CI_JOB_NAME, CI_JOB_STAGE, ... (Builder#predefined_variables)
#   pipeline         PredefinedVariables (project + pipeline)
#   yaml             the job's `variables:` with its matched `rules:variables:`
#                    over them, then the root variables (top-level overlaid by
#                    workflow:rules:variables) its `inherit:variables` lets
#                    through, deduplicated (Seed::Build#calculate_yaml_variables!,
#                    Variables::Helpers.merge_variables)
#   CLI              --variables: pipeline variables (user_defined_variables)
#
# Expansion is upstream's two steps, each applied once:
#
#   1. GitLab, Ci::BuildRunnerPresenter#runner_variables:
#      Collection#sort_and_expand_all(keep_undefined: true,
#      expand_file_refs: false, expand_raw_refs: false). Variables are
#      topologically sorted by reference and each is expanded against the
#      ones before it; an unknown reference stays as written, `$$` and `%%`
#      stay, a reference to an `expand: false` variable stays (the runner
#      resolves it). A reference cycle leaves every value unexpanded.
#   2. Runner, JobVariables.Expand (common/variables.go): every non-raw value
#      once through Go's os.Expand, looking keys up in the step-1 list with
#      the runner's own variables (RUNNER_BASE_VARIABLES) in front. Here an
#      unknown name becomes '' and `$$` becomes `$`.
#
# `expand: false` variables are raw in both steps.
module JobEnvironment
  # One variable as upstream's collection holds it. Keys repeat: precedence
  # is "the last one wins", applied only when a value is looked up.
  Variable = Struct.new(:key, :value, :raw, keyword_init: true)

  # The job as its shell sees it.
  #
  # name          job name
  # variables     String => String, what is exported (last of each key,
  #               expanded), CI_JOB_STATUS=running
  # main_script   before_script + script, one entry per line, multi-line
  #               entries intact: one shell runs it (runner writeUserScript)
  # after_script  the after_script entries joined the same way, nil when
  #               there are none: a second shell runs it (writeAfterScript)
  # after_script_timeout_s  seconds after_script may run (Numeric > 0)
  # project_dir   cwd of both shells (CI_PROJECT_DIR)
  # warnings      operating problems worth telling the user (a reference
  #               cycle, a malformed timeout), never fatal: upstream runs
  #               the job anyway
  Job = Struct.new(:name, :variables, :main_script, :after_script, :after_script_timeout_s, :project_dir, :warnings,
                   keyword_init: true) do
    # The variables after_script runs with: the runner overwrites
    # CI_JOB_STATUS with the script's outcome (Build#executeAfterScript).
    def after_script_variables(status)
      raise ArgumentError, "CI_JOB_STATUS must be one of #{JOB_STATUSES_FINAL.join(', ')}, got #{status.inspect}" \
        unless JOB_STATUSES_FINAL.include?(status)

      variables.merge('CI_JOB_STATUS' => status)
    end
  end

  # Runner AfterScriptTimeout (common/consts.go): after_script's limit
  # unless the job sets RUNNER_AFTER_SCRIPT_TIMEOUT.
  AFTER_SCRIPT_TIMEOUT_S = 5 * 60
  AFTER_SCRIPT_TIMEOUT_VARIABLE = 'RUNNER_AFTER_SCRIPT_TIMEOUT'

  # Go time.ParseDuration units, in seconds.
  GO_DURATION_UNITS_S = { 'ns' => 1e-9, 'us' => 1e-6, "\u00b5s" => 1e-6, "\u03bcs" => 1e-6, 'ms' => 1e-3,
                          's' => 1, 'm' => 60, 'h' => 3600 }.freeze
  GO_DURATION_ELEMENT = /(\d+\.?\d*|\.\d+)(ns|us|\u00b5s|\u03bcs|ms|s|m|h)/
  GO_DURATION = /\A([+-]?)((?:#{GO_DURATION_ELEMENT.source})+)\z/

  # Runner BuildRunRuntimeState values after_script can see. `canceled` and
  # `timedout` are not produced locally.
  JOB_STATUSES_FINAL = %w[success failed].freeze

  # The runner variables (Build#GetDefaultVariables) a local run can know.
  # Before the job's variables, so a yaml variable of the same name wins,
  # as upstream. CI_PROJECT_DIR is already a pipeline predefined variable
  # here. Left out: CI_BUILDS_DIR, CI_CONCURRENT_*, CI_JOB_TIMEOUT,
  # CI_JOB_IMAGE (nothing runs in a container) and every job-only variable
  # GitLab assigns (CI_JOB_ID, CI_JOB_TOKEN, CI_PIPELINE_ID, ...).
  RUNNER_BASE_VARIABLES = { 'CI_SERVER' => 'yes', 'CI_JOB_STATUS' => 'running' }.freeze

  # The shell options the runner's bash script starts with
  # (shells/bash.go BashWriter#Finish): pipefail when the shell has it,
  # errexit, noclobber off. Prepended to the main script and to
  # after_script, which the runner generates the same way.
  SHELL_PRELUDE = "if set -o | grep pipefail > /dev/null; then set -o pipefail; fi; set -o errexit\n" \
                  "set +o noclobber\n"

  # Upstream Entry::Variable key validation (alphanumeric: letters, digits,
  # underscore). Also what keeps a key safe to write after `export`.
  KEY_PATTERN = /\A[A-Za-z0-9_]+\z/

  # A job's variables that cannot be exported (operating error: bad config
  # or --variables); the command reports it.
  Error = Class.new(StandardError)

  module_function

  # @param result [PipelineBuilder::Result] from PipelineBuilder.build, ok
  # @param name [String] a job of result.pipeline_jobs
  # @param cli_variables [Hash] --variables, String => String
  # @param project_dir [String] absolute
  # @return [Job]
  def build(result, name, cli_variables:, project_dir:)
    raise ArgumentError, 'result must be an ok PipelineBuilder.build result' unless result.ok? && result.pipeline_jobs
    raise ArgumentError, "job '#{name}' is not in this pipeline" unless result.pipeline_jobs.key?(name)

    job = result.pipeline_jobs.fetch(name)
    listed = variable_list(result, name, job, cli_variables)
    bad_key = listed.map(&:key).find { |key| !KEY_PATTERN.match?(key) }
    raise Error, "job '#{name}': variable name '#{bad_key}' must contain only letters, digits and '_'" if bad_key

    expanded, warnings = server_expand(listed)
    variables = last_wins(runner_expand(variable_list_from(RUNNER_BASE_VARIABLES) + expanded))
    timeout_s, timeout_warning = after_script_timeout_s(variables[AFTER_SCRIPT_TIMEOUT_VARIABLE])
    Job.new(
      name: name,
      variables: variables,
      main_script: join_commands(job['before_script'], job['script']),
      after_script: job['after_script'].nil? || Array(job['after_script']).empty? ? nil : join_commands(job['after_script']),
      after_script_timeout_s: timeout_s,
      project_dir: project_dir,
      warnings: warnings + [timeout_warning].compact
    )
  end

  # Runner Build#getStageTimeoutContexts for RUNNER_AFTER_SCRIPT_TIMEOUT:
  # blank, malformed, negative or zero keeps the default (the last three
  # with a warning, as the runner logs). There is no job timeout to clamp
  # to locally.
  #
  # @return [Array(Numeric, String|nil)] seconds, warning
  def after_script_timeout_s(raw)
    return [AFTER_SCRIPT_TIMEOUT_S, nil] if raw.nil? || raw.strip.empty?

    seconds = go_duration_s(raw)
    if seconds.nil?
      return [AFTER_SCRIPT_TIMEOUT_S, "Ignoring malformed #{AFTER_SCRIPT_TIMEOUT_VARIABLE} timeout: #{raw}"]
    end
    if seconds.negative?
      return [AFTER_SCRIPT_TIMEOUT_S, "Ignoring relative #{AFTER_SCRIPT_TIMEOUT_VARIABLE} timeout: #{raw}"]
    end

    [seconds.zero? ? AFTER_SCRIPT_TIMEOUT_S : seconds, nil]
  end

  # Go time.ParseDuration ("1m30s", "1.5h", "300ms", "0"), nil when it would
  # error. Overflow is not checked.
  def go_duration_s(text)
    return 0 if %w[0 +0 -0].include?(text)

    match = GO_DURATION.match(text)
    return nil unless match

    total = match[2].scan(GO_DURATION_ELEMENT).sum { |number, unit| number.to_f * GO_DURATION_UNITS_S.fetch(unit) }
    match[1] == '-' ? -total : total
  end

  # Upstream order (module comment), before any expansion.
  #
  # @return [Array<Variable>]
  def variable_list(result, name, job, cli_variables)
    root = yaml_variables(result.config['variables']).merge(yaml_variables(result.workflow_variables))
    inherited = PipelineBuilder.inherited_root_variables(name, job, root)
    own = yaml_variables(job['variables'])
    yaml = own.merge(inherited.reject { |key, _| own.key?(key) })

    variable_list_from(PipelineBuilder.job_predefined_variables(name, job)) +
      variable_list_from(result.predefined_variables) +
      yaml.values +
      variable_list_from(cli_variables)
  end

  # `variables:` as key => Variable: `KEY: value` or
  # `KEY: {value:, expand:, description:, options:}`; a nil value is ''
  # (upstream config_value.to_s), `expand: false` is raw.
  #
  # @raise [Error] when not a mapping
  def yaml_variables(raw)
    return {} if raw.nil?
    raise Error, "variables config should be a hash of key value pairs, got #{raw.class}" unless raw.is_a?(Hash)

    raw.to_h do |key, entry|
      key = key.to_s
      variable = if entry.is_a?(Hash)
                   Variable.new(key: key, value: entry['value'].to_s, raw: entry['expand'] == false)
                 else
                   Variable.new(key: key, value: entry.to_s, raw: false)
                 end
      [key, variable]
    end
  end

  def variable_list_from(hash)
    hash.map { |key, value| Variable.new(key: key.to_s, value: value.to_s, raw: false) }
  end

  def last_wins(variables)
    variables.to_h { |variable| [variable.key, variable.value] }
  end

  # Runner writeCommands: each entry is one command, a multi-line entry
  # stays one command. nil phases are absent.
  def join_commands(*phases)
    phases.compact.flat_map { |phase| Array(phase) }.map(&:to_s).join("\n")
  end

  # -- Step 1: GitLab ------------------------------------------------------

  # Upstream Collection::Item::VARIABLES_REGEXP: `$$`, `%%`, `$KEY`,
  # `${KEY}`, `%KEY%` (the Windows form is expanded by GitLab too).
  SERVER_REFERENCE = /\$\$|%%|\$(?<key>[a-zA-Z_][a-zA-Z0-9_]*)|\${\g<key>?}|%\g<key>%/

  # Collection::Sort over a list with repeated keys: a reference depends on
  # every variable of that name. Nodes are list indices: two equal entries
  # are still two variables (upstream sorts Item objects by identity).
  class ReferenceSort
    include TSort

    def initialize(variables)
      @variables = variables
      @indices_by_key = variables.each_index.group_by { |index| variables[index].key }
    end

    # @return [Array<Variable>] dependencies first
    def sorted
      tsort.map { |index| @variables[index] }
    end

    def tsort_each_node(&block)
      @variables.each_index(&block)
    end

    def tsort_each_child(index, &block)
      JobEnvironment.references(@variables[index]).each { |key| @indices_by_key.fetch(key, []).each(&block) }
    end

    # Upstream Sort#errors: only components of more than one variable are
    # cycles; `FOO: $FOO` alone is not.
    def cycle_error
      cycles = each_strongly_connected_component.filter_map do |component|
        component.map { |index| @variables[index].key }.inspect if component.size > 1
      end
      "circular variable reference detected: #{cycles.join(', ')}" unless cycles.empty?
    end
  end

  # Item#depends_on: the keys a non-raw value references.
  def references(variable)
    return [] if variable.raw
    return [] unless variable.value.include?('$') || variable.value.include?('%')

    variable.value.scan(SERVER_REFERENCE).flatten.compact
  end

  # Collection#sort_and_expand_all(keep_undefined: true,
  # expand_file_refs: false, expand_raw_refs: false).
  #
  # @return [Array(Array<Variable>, Array<String>)] variables, warnings
  def server_expand(variables)
    sort = ReferenceSort.new(variables)
    if (error = sort.cycle_error)
      return [variables, ["#{error}; variables are passed unexpanded, as upstream does"]]
    end

    expanded = []
    latest = {}
    sort.sorted.each do |variable|
      if references(variable).any?
        variable = Variable.new(key: variable.key, value: server_expand_value(variable.value, latest), raw: false)
      end
      expanded << variable
      latest[variable.key] = variable
    end
    [expanded, []]
  end

  # Collection#expand_value: a known non-raw variable gives its value; a
  # raw one and an unknown name stay as written.
  def server_expand_value(value, latest)
    value.gsub(SERVER_REFERENCE) do
      match = Regexp.last_match
      key = match[:key]
      next match[0] unless key

      variable = latest[key]
      variable.nil? || variable.raw ? match[0] : variable.value
    end
  end

  # -- Step 2: runner ------------------------------------------------------

  # JobVariables.Expand: each non-raw value once through os.Expand, every
  # lookup against the list as given (values not yet expanded).
  #
  # @return [Array<Variable>]
  def runner_expand(variables)
    lookup = last_wins(variables)
    variables.map do |variable|
      next variable if variable.raw

      Variable.new(key: variable.key, value: os_expand(variable.value) { |key| runner_value(lookup, key) }, raw: false)
    end
  end

  # JobVariables.value: `$` is itself, shell specials are '', unknown is ''.
  def runner_value(lookup, key)
    return '$' if key == '$'
    return '' if '*#@!?0123456789'.include?(key) && key.length == 1

    lookup.fetch(key, '')
  end

  # Go os.Expand (src/os/env.go), byte for byte for ASCII, which is all its
  # syntax uses.
  def os_expand(text)
    return text unless text.include?('$')

    out = +''
    i = 0
    j = 0
    while j < text.length
      if text[j] == '$' && j + 1 < text.length
        out << text[i...j]
        name, width = go_shell_name(text[(j + 1)..])
        if name.empty? && width.positive?
          # invalid syntax: eaten
        elsif name.empty?
          out << '$'
        else
          out << yield(name)
        end
        j += width
        i = j + 1
      end
      j += 1
    end
    out << text[i..]
  end

  GO_SHELL_SPECIAL = '*#$@!?-0123456789'

  # Go os.getShellName: [name, characters consumed after the `$`].
  def go_shell_name(rest)
    if rest[0] == '{'
      return [rest[1], 3] if rest.length > 2 && GO_SHELL_SPECIAL.include?(rest[1]) && rest[2] == '}'

      close = rest.index('}', 1)
      return ['', 1] if close.nil? # bad syntax: eat "${"
      return ['', 2] if close == 1 # bad syntax: eat "${}"

      return [rest[1...close], close + 1]
    end
    return [rest[0], 1] if GO_SHELL_SPECIAL.include?(rest[0])

    name = rest[/\A[A-Za-z0-9_]*/]
    [name, name.length]
  end
end
