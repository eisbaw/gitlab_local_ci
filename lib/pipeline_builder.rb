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
require_relative 'parallel_expander'

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
#   parallel:              expand_parallel    (Config#normalized_jobs: instances,
#                                              needs/dependencies fanned out)
#   .pre/.post, stage check stages, stage_errors (YamlProcessor, on the composed jobs)
#   workflow:rules         apply_workflow_rules
#   job rules              filter_jobs_by_rules
#   only .pre/.post jobs   drop_only_edge_stage_jobs (Chain::Populate)
#
# resolve_config stops after composing the jobs (the static config lint
# validates);
# build continues through the rules (the jobs of one pipeline).
module PipelineBuilder
  # Upstream Config::Stages::EDGES: always first and last, never declared.
  EDGE_PRE = '.pre'
  EDGE_POST = '.post'
  EDGE_STAGES = [EDGE_PRE, EDGE_POST].freeze

  # Stages when `stages:` is absent (upstream Entry::Stages.default).
  DEFAULT_STAGES = [EDGE_PRE, 'build', 'test', 'deploy', EDGE_POST].freeze

  # Stage of a job without `stage:` (upstream Entry::Job default).
  DEFAULT_JOB_STAGE = 'test'

  # Upstream Ci::Pipeline.rules_failure_message (Chain::Populate), link
  # markup dropped. Why the jobs of a pipeline that has jobs only in
  # .pre/.post are dropped.
  ONLY_EDGE_STAGE_JOBS_MESSAGE = 'only .pre/.post jobs left: The resulting pipeline would have been empty. ' \
                                 'Review the rules configuration.'

  # Printed by every command when Result#workflow_skipped.
  WORKFLOW_SKIPPED_MESSAGE = 'workflow:rules: matched no rule, no pipeline is created'

  # What a pipeline is built for. One per CLI invocation, the same for every
  # subcommand.
  #
  # project_dir     repository root: include:local base, exists:/changes:,
  #                 CI_PROJECT_DIR and the git-derived CI_COMMIT_* vars
  # gitlab_dir      upstream checkout (include:template source), may be nil
  # pipeline_source CI_PIPELINE_SOURCE, an upstream source name
  #                 (PredefinedVariables::SOURCES)
  # ref             --ref: nil/'HEAD' (the checkout's branch or tag), NAME,
  #                 refs/heads/NAME or refs/tags/NAME (PredefinedVariables
  #                 .resolve_ref)
  # variables       CLI --variables (String => String), highest precedence
  Context = Struct.new(:project_dir, :gitlab_dir, :pipeline_source, :ref, :variables, keyword_init: true) do
    # --project wins; otherwise the directory holding the entry file, which
    # is where include:local paths have always been resolved from.
    # --pipeline aliases (merge_request, manual) become upstream names here.
    def self.from_options(options)
      entry = options.fetch(:entry)
      new(
        project_dir: File.expand_path(options[:project] || File.dirname(entry)),
        gitlab_dir: options[:gitlab_dir],
        pipeline_source: PredefinedVariables.canonical_source(options[:pipeline] || 'push'),
        ref: options[:ref],
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
  #                 Config#to_hash). A visible `parallel:` job is replaced,
  #                 in place, by its instances (ParallelExpander), so
  #                 every command sees 'job 1/2' and 'job: [aws]'.
  # workflow_skipped workflow:rules created no pipeline (build only)
  # pipeline_jobs   name => job config of the jobs this pipeline creates,
  #                 rule attributes applied, config order (build only)
  # excluded_jobs   name => reason, visible jobs rules dropped (build only)
  # predefined_variables  the pipeline's PredefinedVariables (build only):
  #                 read from git once, here, so a job's environment
  #                 (JobEnvironment) sees the set rules saw
  # workflow_variables    `variables:` of the matched workflow rule, String
  #                 => String, empty when none (build only)
  Result = Struct.new(:config, :job_definitions, :errors, :workflow_skipped,
                      :pipeline_jobs, :excluded_jobs, :predefined_variables, :workflow_variables,
                      keyword_init: true) do
    def ok?
      errors.empty?
    end

    def stages
      PipelineBuilder.stages(config)
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
  # @param predefined [Hash, nil] predefined_variables(context), computed
  #   here when nil
  # @return [Result] config or errors
  def resolve_config(entry, context, predefined: nil)
    raise ArgumentError, "context must be a PipelineBuilder::Context, got #{context.class}" unless context.is_a?(Context)

    begin
      predefined ||= predefined_variables(context)
    rescue PredefinedVariables::RefError => e
      return failure(e.message)
    end

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

    # Before flatten_lists: flattening would hide the nesting depth.
    commands_errors = commands_errors(config)
    return Result.new(errors: commands_errors) unless commands_errors.empty?

    config = flatten_lists(config)
    job_definitions = begin
      compose_jobs(config)
    rescue ConfigError => e
      return failure(e.message)
    end

    job_definitions, parallel_errors = expand_parallel(job_definitions)
    return Result.new(errors: parallel_errors) unless parallel_errors.empty?

    stage_errors = stage_errors(job_definitions, stages(config))
    return Result.new(errors: stage_errors) unless stage_errors.empty?

    Result.new(config: config, job_definitions: job_definitions, errors: [])
  end

  # Upstream Config#normalized_jobs over the composed jobs: entry
  # validation of `parallel:` first (Entry::Product::Parallel), then the
  # Normalizer (ParallelExpander). Before the stage check, which upstream
  # runs on the normalized jobs, and before rules.
  #
  # @return [Array(Hash, Array<String>)] [jobs, errors]
  def expand_parallel(job_definitions)
    errors = ParallelExpander.errors(job_definitions)
    return [job_definitions, errors] unless errors.empty?

    ParallelExpander.expand(job_definitions)
  end

  # The pipeline's stages, upstream Config::Stages#inject_edge_stages!:
  # .pre first and .post last, moved there if the user listed them
  # elsewhere. Absent `stages:` gives DEFAULT_STAGES. A `stages:` that is
  # not a non-empty list is returned as-is, as upstream does (its own
  # validation reports it).
  #
  # Derived on every call rather than written into config, so config stays
  # what the user wrote and MockServer#create_pipeline (raw configs) gets
  # the same answer.
  def stages(config)
    declared = config['stages']
    return DEFAULT_STAGES if declared.nil?
    return declared unless declared.is_a?(Array) && !declared.empty?

    [EDGE_PRE, *(declared - EDGE_STAGES), EDGE_POST]
  end

  # Upstream YamlProcessor#validate_job_stage!, for every visible job; a
  # job without `stage:` is in DEFAULT_JOB_STAGE and checked too
  # (normalized jobs carry the default). Hidden templates are not jobs.
  #
  # @return [Array<String>] empty when valid
  def stage_errors(job_definitions, stages)
    # Entry::Stages validation (nested lists are flattened by now).
    unless stages.is_a?(Array) && stages.all?(String)
      return ["stages config should be an array of strings or a nested array of strings up to 10 levels deep"]
    end

    visible_jobs(job_definitions).filter_map do |name, job|
      stage = job.fetch('stage', nil)
      stage = DEFAULT_JOB_STAGE if stage.nil?
      next if stage.is_a?(String) && stages.include?(stage)

      "#{name} job: chosen stage #{stage} does not exist; available stages are #{stages.join(', ')}"
    end
  end

  # The jobs of one pipeline: resolve_config, then workflow and job rules.
  #
  # @return [Result] with pipeline fields set, or errors
  def build(entry, context)
    predefined = begin
      predefined_variables(context)
    rescue PredefinedVariables::RefError => e
      return failure(e.message)
    end
    result = resolve_config(entry, context, predefined: predefined)
    return result unless result.ok?

    evaluated = begin
      evaluate_rules(result.config, jobs: result.jobs, predefined: predefined,
                                    cli_variables: context.variables, project_dir: context.project_dir)
    rescue StandardError => e
      return failure("Error evaluating rules: #{e.message}")
    end
    Result.new(config: result.config, job_definitions: result.job_definitions, errors: [],
               predefined_variables: predefined, **evaluated)
  end

  # Workflow rules, then job rules, over a resolved config and its visible
  # composed jobs (Result#jobs).
  #
  # Variables, lowest precedence first: predefined CI_* (pipeline, then the
  # job's own CI_JOB_*/CI_NODE_*), root variables
  # (top-level `variables:` overlaid by the matched workflow rule's
  # `variables:`, upstream Chain::Seed#root_variables), the job's own
  # `variables:` (matrix variables of a parallel instance included), CLI
  # variables (pipeline variables outrank every .gitlab-ci.yml variable,
  # doc/ci/variables "CI/CD variable precedence"). Each job's rules see
  # only the root variables its `inherit:variables` lets through, then its
  # own (Seed::Build#calculate_yaml_variables!: yaml_variables, which
  # Context::Build puts in the rules context); predefined and CLI
  # variables are not root variables and always reach it.
  #
  # @return [Hash] { workflow_skipped:, pipeline_jobs:, excluded_jobs:,
  #   workflow_variables: }
  # @raise [StandardError] on a rule the evaluator rejects
  def evaluate_rules(config, jobs:, predefined:, cli_variables:, project_dir:)
    cli = cli_variables.to_h { |k, v| [k.to_s, v.to_s] }
    root = root_variables(config)
    workflow = apply_workflow_rules(config, predefined.merge(root).merge(cli), project_dir: project_dir)
    if workflow[:filtered]
      return { workflow_skipped: true, pipeline_jobs: {}, excluded_jobs: {}, workflow_variables: {} }
    end

    root = root.merge(workflow[:variables])
    pipeline_jobs, excluded_jobs = filter_jobs_by_rules(jobs, project_dir: project_dir) do |name, job|
      predefined.merge(job_predefined_variables(name, job))
                .merge(inherited_root_variables(name, job, root))
                .merge(variable_values(job['variables'])).merge(cli)
    end
    pipeline_jobs, excluded_jobs = drop_only_edge_stage_jobs(pipeline_jobs, excluded_jobs)
    { workflow_skipped: false, pipeline_jobs: pipeline_jobs, excluded_jobs: excluded_jobs,
      workflow_variables: workflow[:variables] }
  end

  # Upstream Chain::Populate#no_pipeline_to_create?: .pre/.post jobs alone
  # are not a pipeline (gitlab-org/gitlab#198518), so none of them run.
  # Expressed as the same outcome as "rules left no job": every kept job
  # moves to excluded with upstream's reason, and each command reports an
  # empty pipeline its usual way (one convention for that is TASK-36).
  #
  # @return [Array(Hash, Hash)] [kept, excluded]
  def drop_only_edge_stage_jobs(kept, excluded)
    return [kept, excluded] if kept.empty?
    return [kept, excluded] unless kept.values.all? { |job| EDGE_STAGES.include?(job['stage']) }

    [{}, excluded.merge(kept.transform_values { ONLY_EDGE_STAGE_JOBS_MESSAGE })]
  end

  def failure(message)
    Result.new(errors: [message])
  end

  # @raise [PredefinedVariables::RefError]
  def predefined_variables(context)
    PredefinedVariables.build(project_dir: context.project_dir, pipeline_source: context.pipeline_source,
                              ref: context.ref)
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

  # Upstream Entry::Commands: StringOrNestedArrayOfStringsValidator with
  # max_level 10 (the outer list counts as a level).
  COMMANDS_NESTING_LEVEL_MAX = 10
  COMMANDS_KEYS = %w[before_script script after_script].freeze

  # Entry::Commands errors for every script list upstream validates: root
  # and default: before_script/after_script, and script/before_script/
  # after_script of every visible job (hidden ones are Entry::Hidden, not
  # validated). A key set to null counts as unspecified. E.g. an unquoted
  # `- echo "a: b"` is a YAML mapping, not a string. Text as upstream lint
  # prints it: "<location> config <message>", downcased (Validator#messages).
  #
  # @param config [Hash] resolved config, lists not yet flattened
  # @return [Array<String>] empty when valid
  def commands_errors(config)
    entries = [[nil, config.slice('before_script', 'after_script')]]
    entries << ['default', config['default']] if config['default'].is_a?(Hash)
    config.each do |key, value|
      next unless CiKeywords.job_entry?(key, value) && !CiKeywords.hidden?(key)

      entries << ["jobs:#{key}", value]
    end

    entries.flat_map do |prefix, entry|
      COMMANDS_KEYS.filter_map do |key|
        next unless entry.key?(key)

        value = entry[key]
        next if value.nil? || string_or_nested_array_of_strings?(value, COMMANDS_NESTING_LEVEL_MAX)

        location = [prefix, key].compact.join(':')
        message = "#{location} config should be a string or a nested array of strings " \
                  "up to #{COMMANDS_NESTING_LEVEL_MAX} levels deep"
        message.downcase
      end
    end
  end

  # Upstream validate_string || validate_nested_array(value, levels).
  def string_or_nested_array_of_strings?(value, levels)
    return true if value.is_a?(String)
    return false if levels <= 0 || !value.is_a?(Array)

    value.all? { |item| string_or_nested_array_of_strings?(item, levels - 1) }
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

    # Passed even when the directory is missing: only an include:template
    # needs the checkout, and IncludeProcessor reports that one (TASK-43).
    gitlab_templates_path = gitlab_dir && File.join(gitlab_dir, 'lib', 'gitlab', 'ci', 'templates')

    IncludeProcessor.new(
      project_path: project_dir,
      gitlab_templates_path: gitlab_templates_path,
      variables: variables,
      server_url: PredefinedVariables.server_url(project_dir: project_dir, variables: variables)
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
    variable_values(config['variables'])
  end

  # A `variables:` entry (root or job) as String => String; a non-Hash is
  # no variables here (JobEnvironment reports it for a job that runs).
  def variable_values(raw)
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

  # CI_JOB_NAME, CI_JOB_STAGE, ... for one job's rules. Upstream appends
  # them first (Builder#scoped_variables_for_pipeline_seed), so yaml and
  # CLI variables of the same name win.
  def job_predefined_variables(name, job)
    stage = job['stage'].nil? ? DEFAULT_JOB_STAGE : job['stage'].to_s
    index, total = parallel_instance(job) || [nil, 1]
    PredefinedVariables.job_variables(name: name.to_s, stage: stage, when_value: job['when'],
                                      node_index: index, node_total: total)
  end

  # [index, total] of a parallel instance (ParallelExpander#instance_job),
  # nil for any other job.
  def parallel_instance(job)
    parallel = job['parallel']
    return nil unless parallel.is_a?(Hash) && parallel.key?('instance')

    [parallel.fetch('instance'), parallel.fetch('total')]
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

      job_vars = yield(name, job_config)

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
    same_pipeline_needs(needs_config).reject { |_name, optional| optional }.map(&:first)
  end

  # Needs on jobs of this pipeline, as [job name, optional] pairs, config
  # order: String or {job:, optional:}; {project:}/{pipeline:}/{ref:} needs
  # are cross-pipeline (upstream CrossDependency, not a build need).
  def same_pipeline_needs(needs_config)
    return [] unless needs_config.is_a?(Array)

    needs_config.filter_map do |need|
      case need
      when String then [need, false]
      when Hash
        next if %w[project pipeline ref].any? { |k| need.key?(k) }
        next unless need['job']

        [need['job'], need['optional'] == true]
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
