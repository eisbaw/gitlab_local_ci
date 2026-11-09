# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require_relative 'ci_yaml'
require_relative 'ci_keywords'
require_relative 'include_processor'
require_relative 'extends_resolver'
require_relative 'reference_resolver'
require_relative 'rules_evaluator'
require_relative 'predefined_variables'

# Config -> pipeline construction shared by every subcommand, so lint, dag,
# dry-run, run and export-just see the same jobs.
#
# Upstream order (gitlab/lib/gitlab/ci/config.rb#build_config, then
# Pipeline::Chain), and where each step lives here:
#
#   load YAML              load_yaml
#   includes               process_includes   (include:rules see predefined + CLI vars)
#   extends                ExtendsResolver    (every key a root, as upstream Extendable)
#   !reference             ReferenceResolver  (after extends, before split)
#   nested lists           flatten_lists      (upstream Entry values)
#   default:/inherit:      compose_jobs       (on the split jobs, before rules)
#   workflow:rules         apply_workflow_rules
#   job rules              filter_jobs_by_rules
#
# resolve_config stops after composing the jobs (the static config lint
# validates);
# build continues through the rules (the jobs of one pipeline).
module PipelineBuilder
  # Upstream's default is .pre build test deploy .post (TASK-17).
  DEFAULT_STAGES = %w[build test deploy].freeze

  # Printed by every command when Result#workflow_skipped.
  WORKFLOW_SKIPPED_MESSAGE = 'workflow:rules: matched no rule, no pipeline is created'

  # What a pipeline is built for. One per CLI invocation, the same for every
  # subcommand.
  #
  # project_dir     repository root: include:local base, exists:/changes:,
  #                 CI_PROJECT_DIR and the git-derived CI_COMMIT_* vars
  # gitlab_dir      upstream checkout (include:template source), may be nil
  # pipeline_source CI_PIPELINE_SOURCE
  # variables       CLI --variables (String => String), highest precedence
  Context = Struct.new(:project_dir, :gitlab_dir, :pipeline_source, :variables, keyword_init: true) do
    # --project wins; otherwise the directory holding the entry file, which
    # is where include:local paths have always been resolved from.
    def self.from_options(options)
      entry = options.fetch(:entry)
      new(
        project_dir: File.expand_path(options[:project] || File.dirname(entry)),
        gitlab_dir: options[:gitlab_dir],
        pipeline_source: options[:pipeline] || 'push',
        variables: (options[:variables] || {}).to_h { |k, v| [k.to_s, v.to_s] }
      )
    end
  end

  # Outcome of resolve_config / build. Errors are data: when errors is
  # non-empty every other field is nil and the caller reports the errors.
  #
  # config          merged, extended, references resolved, lists flattened
  #                 (globals, templates, jobs); defaults NOT applied
  # job_definitions name => job, every job entry (hidden templates included,
  #                 untouched), config order, visible jobs with default:
  #                 and legacy globals applied (compose_jobs). Stored, not
  #                 derived from config: once defaults apply a job is no
  #                 longer its config entry (upstream Root#jobs_value vs
  #                 Config#to_hash).
  # workflow_skipped workflow:rules created no pipeline (build only)
  # pipeline_jobs   name => job config of the jobs this pipeline creates,
  #                 rule attributes applied, config order (build only)
  # excluded_jobs   name => reason, visible jobs rules dropped (build only)
  Result = Struct.new(:config, :job_definitions, :errors, :workflow_skipped,
                      :pipeline_jobs, :excluded_jobs, keyword_init: true) do
    def ok?
      errors.empty?
    end

    def stages
      config['stages'] || DEFAULT_STAGES
    end

    # Visible jobs before rules: the static job set.
    def jobs
      PipelineBuilder.visible_jobs(job_definitions)
    end
  end

  # Operating error while loading the entry file; becomes Result#errors.
  LoadError = Class.new(StandardError)

  # Invalid default:/inherit:, in upstream's wording; becomes Result#errors.
  ConfigError = Class.new(StandardError)

  module_function

  # Static config: load, includes, extends, !reference, nested lists,
  # defaults.
  #
  # @param entry [String] path to .gitlab-ci.yml
  # @param context [Context]
  # @return [Result] config or errors
  def resolve_config(entry, context, predefined: predefined_variables(context))
    raise ArgumentError, "context must be a PipelineBuilder::Context, got #{context.class}" unless context.is_a?(Context)

    begin
      config = load_yaml(entry)
    rescue LoadError => e
      return failure(e.message)
    end

    begin
      config = process_includes(
        config,
        project_dir: context.project_dir,
        gitlab_dir: context.gitlab_dir,
        variables: predefined.merge(context.variables)
      )
    rescue IncludeDepthExceededError => e
      return failure("Include depth exceeded: #{e.depth} > #{e.max_depth}")
    rescue StandardError => e
      return failure("Error processing includes: #{e.message}")
    end

    # Upstream's texts name the entry and the keyword ("<key>: ... in
    # `extends`"), so they are reported as-is, like upstream lint does.
    begin
      config = ExtendsResolver.new.resolve_extends(config)
    rescue ExtendsResolver::ExtensionError => e
      return failure(e.message)
    end

    begin
      config = ReferenceResolver.resolve(config)
    rescue ReferenceResolver::Error => e
      return failure(e.message)
    end

    config = flatten_lists(config)
    begin
      Result.new(config: config, job_definitions: compose_jobs(config), errors: [])
    rescue ConfigError => e
      failure(e.message)
    end
  end

  # The jobs of one pipeline: resolve_config, then workflow and job rules.
  #
  # @return [Result] with pipeline fields set, or errors
  def build(entry, context)
    predefined = predefined_variables(context)
    result = resolve_config(entry, context, predefined: predefined)
    return result unless result.ok?

    evaluated = begin
      evaluate_rules(result.config, jobs: result.jobs, predefined: predefined,
                                    cli_variables: context.variables, project_dir: context.project_dir)
    rescue StandardError => e
      return failure("Error evaluating rules: #{e.message}")
    end
    Result.new(config: result.config, job_definitions: result.job_definitions, errors: [], **evaluated)
  end

  # Workflow rules, then job rules, over a resolved config and its visible
  # composed jobs (Result#jobs).
  #
  # Variables, lowest precedence first: predefined CI_*, root variables
  # (top-level `variables:` overlaid by the matched workflow rule's
  # `variables:`, upstream Chain::Seed#root_variables), CLI variables
  # (pipeline variables outrank every .gitlab-ci.yml variable, doc/ci/variables
  # "CI/CD variable precedence"). Each job's rules see only the root
  # variables its `inherit:variables` lets through (Seed::Build
  # #calculate_yaml_variables!); predefined and CLI variables are not root
  # variables and always reach it.
  #
  # @return [Hash] { workflow_skipped:, pipeline_jobs:, excluded_jobs: }
  # @raise [StandardError] on a rule the evaluator rejects
  def evaluate_rules(config, jobs:, predefined:, cli_variables:, project_dir:)
    cli = cli_variables.to_h { |k, v| [k.to_s, v.to_s] }
    root = root_variables(config)
    workflow = apply_workflow_rules(config, predefined.merge(root).merge(cli), project_dir: project_dir)
    if workflow[:filtered]
      return { workflow_skipped: true, pipeline_jobs: {}, excluded_jobs: {} }
    end

    root = root.merge(workflow[:variables])
    pipeline_jobs, excluded_jobs = filter_jobs_by_rules(jobs, project_dir: project_dir) do |name, job|
      predefined.merge(inherited_root_variables(name, job, root)).merge(cli)
    end
    { workflow_skipped: false, pipeline_jobs: pipeline_jobs, excluded_jobs: excluded_jobs }
  end

  def failure(message)
    Result.new(errors: [message])
  end

  def predefined_variables(context)
    PredefinedVariables.build(project_dir: context.project_dir, pipeline_source: context.pipeline_source)
  end

  # @return [Hash] parsed config
  # @raise [LoadError] unreadable file, invalid YAML, or not a mapping
  def load_yaml(entry)
    raise LoadError, "File not found: #{entry}" unless File.exist?(entry)

    content = begin
      File.read(entry)
    rescue Errno::EACCES
      raise LoadError, "Permission denied reading file: #{entry}"
    rescue StandardError => e
      raise LoadError, "Error reading file #{entry}: #{e.message}"
    end

    config = begin
      CiYaml.load(content)
    rescue Psych::SyntaxError => e
      raise LoadError, "YAML syntax error: #{e.message}"
    rescue StandardError => e
      raise LoadError, "Failed to parse YAML: #{e.message}"
    end
    raise LoadError, 'Configuration must be a YAML hash/dictionary' unless config.is_a?(Hash)

    config
  end

  # Upstream entry values flatten nested lists completely: Entry::Commands
  # (script, before_script, after_script) Array(config).flatten,
  # ComposableArray (rules, needs, services, cache) [config].flatten,
  # Entry::Stages config.flatten. That is how a `!reference` or a YAML
  # alias used as one list item contributes its items. Applied here, once,
  # so every consumer (lint, rules, dag, export-just) sees flat lists.
  # Non-Array values are left for validation.
  JOB_LIST_KEYS = %w[script before_script after_script rules needs services cache].freeze
  ROOT_LIST_KEYS = %w[before_script after_script services cache stages].freeze

  def flatten_lists(config)
    config.to_h do |key, value|
      flattened =
        if CiKeywords.job_entry?(key, value) || key == 'default'
          flatten_keys(value, JOB_LIST_KEYS)
        elsif key == 'workflow'
          flatten_keys(value, %w[rules])
        elsif ROOT_LIST_KEYS.include?(key)
          flatten_list(value)
        else
          value
        end
      [key, flattened]
    end
  end

  def flatten_keys(entry, keys)
    return entry unless entry.is_a?(Hash)

    entry.to_h { |key, value| [key, keys.include?(key) ? flatten_list(value) : value] }
  end

  def flatten_list(value)
    value.is_a?(Array) ? value.flatten : value
  end

  # Merge `include:`d files into config (IncludeProcessor). `variables` is
  # the set `include: rules:` are evaluated against.
  #
  # @raise [IncludeDepthExceededError, StandardError] on include failure
  def process_includes(config, project_dir:, gitlab_dir:, variables:)
    return config unless config['include']

    gitlab_templates_path = nil
    if gitlab_dir && Dir.exist?(gitlab_dir)
      gitlab_templates_path = File.join(gitlab_dir, 'lib', 'gitlab', 'ci', 'templates')
    end

    IncludeProcessor.new(
      project_path: project_dir,
      gitlab_templates_path: gitlab_templates_path,
      variables: variables
    ).process_includes(config)
  end

  # Every job entry, hidden templates included, in config order.
  def job_definitions(config)
    config.select { |key, value| CiKeywords.job_entry?(key, value) }
  end

  # Job entries that become jobs: hidden templates excluded.
  def visible_jobs(job_definitions)
    job_definitions.reject { |key, _| CiKeywords.hidden?(key) }
  end

  # Every job entry as upstream composes it (Entry::Root#compose!), config
  # order. A visible job takes each default it may inherit and does not set
  # itself (Inheritable#inherit!, Job#overwrite_entry). The default replaces
  # the job's entry whole, never deep-merged: a job's own `cache:` drops the
  # default cache entirely. Applied after extends, so a key a job got from
  # a template counts as the job's own. A key set to null is unspecified
  # (Factory: nil value -> Entry::Unspecified) and inherits. Hidden
  # templates get nothing (Entry::Hidden is no Processable).
  #
  # @return [Hash] name => job
  # @raise [ConfigError] invalid default: or inherit:, or a key both in
  #   default: and top-level
  def compose_jobs(config)
    defaults = job_defaults(config)
    job_definitions(config).to_h do |name, job|
      next [name, job] if CiKeywords.hidden?(name)

      inherit_setting(name, job, 'variables') # validated here, read by evaluate_rules
      inherited = defaults.slice(*inheritable_default_keys(name, job)).reject { |key, _| specified?(job, key) }
      [name, job.merge(inherited)]
    end
  end

  # `default:` merged with the legacy top-level globals, unspecified (null)
  # entries dropped. Upstream Entry::Default#overwrite_entry.
  #
  # @raise [ConfigError]
  def job_defaults(config)
    default = config['default'].nil? ? {} : config['default']
    raise ConfigError, 'default config should be a hash' unless default.is_a?(Hash)

    unknown = default.keys - CiKeywords::DEFAULT
    raise ConfigError, "default config contains unknown keys: #{unknown.join(', ')}" unless unknown.empty?

    defaults = default.reject { |_, value| value.nil? }
    CiKeywords::LEGACY_DEFAULT.each do |key|
      next if config[key].nil?
      raise ConfigError, "#{key} is defined in top-level and `default:` entry" if defaults.key?(key)

      defaults[key] = config[key]
    end
    defaults
  end

  # Default keys this job may inherit: its type's inheritable entries
  # (Entry::Job: all of default:; Entry::Bridge, i.e. no script:/run:: only
  # Processable's), narrowed by `inherit:default` (Inherit::Default).
  #
  # @raise [ConfigError]
  def inheritable_default_keys(name, job)
    keys = job.key?('script') || job.key?('run') ? CiKeywords::DEFAULT : CiKeywords::BRIDGE_DEFAULT
    setting = inherit_setting(name, job, 'default')
    return setting ? keys : [] if [true, false].include?(setting)

    unknown = setting - CiKeywords::DEFAULT
    raise ConfigError, "jobs:#{name}:inherit:default config contains unknown values: #{unknown.join(', ')}" unless unknown.empty?

    keys & setting
  end

  # `inherit:<key>` (default or variables): true, false, or a list of names.
  # Absent or null means true (Entry::Inherit defaults).
  #
  # @raise [ConfigError] on another shape, in upstream's wording
  def inherit_setting(name, job, key)
    inherit = job['inherit']
    return true if inherit.nil?
    raise ConfigError, "jobs:#{name}:inherit config should be a hash" unless inherit.is_a?(Hash)

    unknown = inherit.keys - %w[default variables]
    raise ConfigError, "jobs:#{name}:inherit config contains unknown keys: #{unknown.join(', ')}" unless unknown.empty?

    setting = inherit[key]
    return true if setting.nil?
    return setting if [true, false].include?(setting) || (setting.is_a?(Array) && setting.all?(String))

    raise ConfigError, "jobs:#{name}:inherit:#{key} should be a bool or array of strings"
  end

  def specified?(job, key)
    !job[key].nil?
  end

  # The root variables this job inherits (Variables::Helpers
  # #inherit_yaml_variables): all, none, or the listed names.
  def inherited_root_variables(name, job, root_variables)
    setting = inherit_setting(name, job, 'variables')
    return setting ? root_variables : {} if [true, false].include?(setting)

    root_variables.slice(*setting)
  end

  # Top-level `variables:` as String => String. (Include rules do NOT see
  # them; that is upstream's documented scope.)
  def root_variables(config)
    raw = config['variables']
    return {} unless raw.is_a?(Hash)

    raw.to_h do |k, v|
      value =
        if v.is_a?(Hash)
          # `variables: FOO: { value: "...", description: "..." }` form.
          (v['value'] || v[:value] || '').to_s
        elsif v.nil?
          ''
        else
          v.to_s
        end
      [k.to_s, value]
    end
  end

  # Evaluate workflow:rules against `variables`. Returns { variables:,
  # filtered: }: variables are the matched rule's `variables:` (String =>
  # String, empty if none); filtered means workflow rules exist and matched
  # nothing (or matched when: never), so upstream creates no pipeline
  # (Chain::EvaluateWorkflowRules).
  def apply_workflow_rules(config, variables, project_dir:)
    workflow = config['workflow'] || config[:workflow]
    rules = workflow.is_a?(Hash) ? (workflow['rules'] || workflow[:rules]) : nil
    return { variables: {}, filtered: false } if rules.nil?

    context = {
      project_dir: project_dir,
      default_branch: variables['CI_DEFAULT_BRANCH'] || 'main'
    }
    result = RulesEvaluator.evaluate_rules(rules, variables, context: context, mode: :job)

    return { variables: {}, filtered: true } unless result[:matched]
    return { variables: {}, filtered: true } if result[:when] && result[:when].to_s == 'never'

    matched_vars = result[:attributes]['variables']
    rule_variables = matched_vars.is_a?(Hash) ? matched_vars.to_h { |k, v| [k.to_s, v.to_s] } : {}
    { variables: rule_variables, filtered: false }
  end

  # Split jobs into those `rules:` keep and those they drop, with the
  # reason. The block yields (name, job) and returns the variables that
  # job's rules see.
  #
  # A job is kept iff it has no `rules:`, or its first matching rule's
  # `when:` is not `never`. A job with rules but no matching rule is
  # dropped (upstream). Matched rule attributes are merged into the job.
  #
  # @return [Array(Hash, Hash)] [kept name => config, excluded name => reason]
  def filter_jobs_by_rules(jobs, project_dir:)
    kept = {}
    excluded = {}
    jobs.each do |name, job_config|
      rules = job_config['rules'] || job_config[:rules]
      if rules.nil?
        kept[name] = job_config
        next
      end

      # Per-job overlay so rules can reference CI_JOB_NAME / CI_JOB_STAGE.
      job_vars = yield(name, job_config).dup
      job_vars['CI_JOB_NAME']  = name.to_s
      job_vars['CI_JOB_STAGE'] = (job_config['stage'] || job_config[:stage] || 'test').to_s

      context = {
        project_dir: project_dir,
        default_branch: job_vars['CI_DEFAULT_BRANCH'] || 'main'
      }
      result = RulesEvaluator.evaluate_rules(rules, job_vars, context: context, mode: :job)
      if !result[:matched]
        excluded[name] = 'no rule matched'
      elsif result[:when] && result[:when].to_s == 'never'
        excluded[name] = 'matching rule has when: never'
      else
        kept[name] = apply_rule_attributes(job_config, result)
      end
    end

    excluded.merge!(cascade_drop_orphaned_needs(kept))
    [kept, excluded]
  end

  # Rule values override job-level values (upstream: `rules:variables:` win
  # over the job's own `variables:`). `when:` is surfaced on the job so
  # consumers see e.g. `manual`.
  def apply_rule_attributes(job_config, rule_result)
    merged = job_config.dup
    attrs = rule_result[:attributes] || {}

    if (rule_vars = attrs['variables']).is_a?(Hash)
      job_vars = merged['variables'].is_a?(Hash) ? merged['variables'].dup : {}
      rule_vars.each { |k, v| job_vars[k.to_s] = v }
      merged['variables'] = job_vars
    end

    %w[allow_failure start_in needs interruptible].each do |k|
      merged[k] = attrs[k] unless attrs[k].nil?
    end

    merged['when'] = rule_result[:when] if rule_result[:when]
    merged
  end

  # Repeatedly drop any job whose `needs:` reference a job not in the set,
  # until a fixed point. Names containing `/` (cross-project needs) never
  # orphan a job. Bounded: each pass removes at least one job or stops.
  # (Upstream instead fails pipeline creation unless the need is
  # `optional: true`; kept as-is here.)
  #
  # Mutates job_configs. @return [Hash] dropped name => reason
  def cascade_drop_orphaned_needs(job_configs)
    dropped = {}
    loop do
      surviving = job_configs.keys
      orphaned = job_configs.each_with_object({}) do |(name, cfg), acc|
        missing = required_same_pipeline_needs(cfg['needs']).find { |n| !surviving.include?(n) && !n.include?('/') }
        acc[name] = "needs '#{missing}', which is not in this pipeline" if missing
      end
      break if orphaned.empty?

      orphaned.each_key { |n| job_configs.delete(n) }
      dropped.merge!(orphaned)
    end
    dropped
  end

  # Needs the job cannot run without inside this pipeline: drops
  # `optional: true` and cross-project/-pipeline needs ({project:},
  # {pipeline:}, {ref:}), which upstream does not resolve against this
  # pipeline's jobs (entry/need.rb, seed/build.rb#needs_errors).
  def required_same_pipeline_needs(needs_config)
    return [] unless needs_config.is_a?(Array)

    needs_config.filter_map do |need|
      case need
      when String then need
      when Hash
        next if need['optional'] == true
        next if %w[project pipeline ref].any? { |k| need.key?(k) }

        need['job']
      end
    end
  end

  # `needs:` entries as job names (String or {job: ...}); others ignored.
  def needs_job_names(needs_config)
    return [] unless needs_config.is_a?(Array)

    needs_config.map do |need|
      case need
      when String then need
      when Hash then need['job']
      end
    end.compact
  end
end
