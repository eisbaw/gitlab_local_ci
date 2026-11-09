# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'yaml'
require_relative 'ci_keywords'
require_relative 'include_processor'
require_relative 'extends_resolver'
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
#   extends                ExtendsResolver    (TASK-31: hidden roots, key order)
#   !reference             -                  (TASK-8: after extends, before split)
#   default:/inherit:      -                  (TASK-9: on the split jobs, before rules)
#   workflow:rules         apply_workflow_rules
#   job rules              filter_jobs_by_rules
#
# resolve_config stops after extends (the static config lint validates);
# build continues through the rules (the jobs of one pipeline).
module PipelineBuilder
  # Upstream's default is .pre build test deploy .post (TASK-17).
  DEFAULT_STAGES = %w[build test deploy].freeze

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
  # config          merged + extended config (globals, templates, jobs)
  # variables       pipeline variables rules saw (build only)
  # workflow_skipped workflow:rules created no pipeline (build only)
  # pipeline_jobs   name => job config of the jobs this pipeline creates,
  #                 rule attributes applied, config order (build only)
  # excluded_jobs   name => reason, visible jobs rules dropped (build only)
  Result = Struct.new(:config, :errors, :variables, :workflow_skipped,
                      :pipeline_jobs, :excluded_jobs, keyword_init: true) do
    def ok?
      errors.empty?
    end

    def stages
      config['stages'] || DEFAULT_STAGES
    end

    # Every job entry, hidden templates included, in config order.
    def job_definitions
      PipelineBuilder.job_definitions(config)
    end

    # Visible jobs before rules: the static job set.
    def jobs
      PipelineBuilder.visible_jobs(config)
    end
  end

  # Operating error while loading the entry file; becomes Result#errors.
  LoadError = Class.new(StandardError)

  module_function

  # Static config: load, includes, extends.
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

    begin
      config = ExtendsResolver.new.resolve_extends(config)
    rescue StandardError => e
      return failure("Error resolving extends: #{e.message}")
    end

    Result.new(config: config, errors: [])
  end

  # The jobs of one pipeline: resolve_config, then workflow and job rules.
  #
  # @return [Result] with pipeline fields set, or errors
  def build(entry, context)
    predefined = predefined_variables(context)
    result = resolve_config(entry, context, predefined: predefined)
    return result unless result.ok?

    evaluated = begin
      evaluate_rules(result.config, predefined: predefined, cli_variables: context.variables,
                                    project_dir: context.project_dir)
    rescue StandardError => e
      return failure("Error evaluating rules: #{e.message}")
    end
    Result.new(config: result.config, errors: [], **evaluated)
  end

  # Workflow rules, then job rules, over a resolved config.
  #
  # @return [Hash] { variables:, workflow_skipped:, pipeline_jobs:, excluded_jobs: }
  # @raise [StandardError] on a rule the evaluator rejects
  def evaluate_rules(config, predefined:, cli_variables:, project_dir:)
    variables = pipeline_variables(config, predefined: predefined, cli_variables: cli_variables)
    workflow = apply_workflow_rules(config, variables, project_dir: project_dir)
    if workflow[:filtered]
      return { variables: workflow[:variables], workflow_skipped: true, pipeline_jobs: {}, excluded_jobs: {} }
    end

    pipeline_jobs, excluded_jobs = filter_jobs_by_rules(visible_jobs(config), workflow[:variables], project_dir: project_dir)
    { variables: workflow[:variables], workflow_skipped: false, pipeline_jobs: pipeline_jobs, excluded_jobs: excluded_jobs }
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
      YAML.safe_load(content, permitted_classes: [Symbol], aliases: true)
    rescue Psych::SyntaxError => e
      raise LoadError, "YAML syntax error: #{e.message}"
    rescue StandardError => e
      raise LoadError, "Failed to parse YAML: #{e.message}"
    end
    raise LoadError, 'Configuration must be a YAML hash/dictionary' unless config.is_a?(Hash)

    config
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
  def visible_jobs(config)
    job_definitions(config).reject { |key, _| CiKeywords.hidden?(key) }
  end

  # Variables visible to workflow and job rules, lowest precedence first:
  # predefined CI_*, top-level `variables:` defaults, CLI/trigger variables.
  # (Include rules do NOT see top-level `variables:`; that is upstream's
  # documented scope.)
  def pipeline_variables(config, predefined:, cli_variables:)
    variables = predefined.dup
    raw = config['variables']
    if raw.is_a?(Hash)
      raw.each do |k, v|
        variables[k.to_s] =
          if v.is_a?(Hash)
            # `variables: FOO: { value: "...", description: "..." }` form.
            (v['value'] || v[:value] || '').to_s
          elsif v.nil?
            ''
          else
            v.to_s
          end
      end
    end
    cli_variables.each { |k, v| variables[k.to_s] = v.to_s }
    variables
  end

  # Evaluate workflow:rules. Returns { variables:, filtered: }; filtered
  # means workflow rules exist and matched nothing (or matched when: never),
  # so upstream creates no pipeline (Chain::EvaluateWorkflowRules). The
  # matched rule's `variables:` are layered over the input variables.
  def apply_workflow_rules(config, variables, project_dir:)
    workflow = config['workflow'] || config[:workflow]
    rules = workflow.is_a?(Hash) ? (workflow['rules'] || workflow[:rules]) : nil
    return { variables: variables, filtered: false } if rules.nil?

    context = {
      project_dir: project_dir,
      default_branch: variables['CI_DEFAULT_BRANCH'] || 'main'
    }
    result = RulesEvaluator.evaluate_rules(rules, variables, context: context, mode: :job)

    return { variables: variables, filtered: true } unless result[:matched]
    return { variables: variables, filtered: true } if result[:when] && result[:when].to_s == 'never'

    variables = variables.dup
    matched_vars = result[:attributes]['variables']
    matched_vars.each { |k, v| variables[k.to_s] = v.to_s } if matched_vars.is_a?(Hash)
    { variables: variables, filtered: false }
  end

  # Split jobs into those `rules:` keep under `variables` and those they
  # drop, with the reason.
  #
  # A job is kept iff it has no `rules:`, or its first matching rule's
  # `when:` is not `never`. A job with rules but no matching rule is
  # dropped (upstream). Matched rule attributes are merged into the job.
  #
  # @return [Array(Hash, Hash)] [kept name => config, excluded name => reason]
  def filter_jobs_by_rules(jobs, variables, project_dir:)
    kept = {}
    excluded = {}
    jobs.each do |name, job_config|
      rules = job_config['rules'] || job_config[:rules]
      if rules.nil?
        kept[name] = job_config
        next
      end

      # Per-job overlay so rules can reference CI_JOB_NAME / CI_JOB_STAGE.
      job_vars = variables.dup
      job_vars['CI_JOB_NAME']  = name.to_s
      job_vars['CI_JOB_STAGE'] = (job_config['stage'] || job_config[:stage] || 'test').to_s

      context = {
        project_dir: project_dir,
        default_branch: variables['CI_DEFAULT_BRANCH'] || 'main'
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
        missing = needs_job_names(cfg['needs']).find { |n| !surviving.include?(n) && !n.include?('/') }
        acc[name] = "needs '#{missing}', which is not in this pipeline" if missing
      end
      break if orphaned.empty?

      orphaned.each_key { |n| job_configs.delete(n) }
      dropped.merge!(orphaned)
    end
    dropped
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
