# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require_relative 'ci_keywords'
require_relative 'include_processor'
require_relative 'rules_evaluator'

# Config -> pipeline construction shared by every subcommand.
#
# Upstream order (gitlab/lib/gitlab/ci/config.rb#build_config, then
# Pipeline::Chain): load YAML -> includes -> extends -> !reference ->
# normalize -> workflow:rules -> job rules.
module PipelineBuilder
  module_function

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

  # Drop jobs whose `rules:` exclude them under `variables`.
  #
  # A job is kept iff it has no `rules:`, or its first matching rule's
  # `when:` is not `never`. A job with rules but no matching rule is
  # dropped (upstream). Matched rule attributes are merged into the job.
  def filter_jobs_by_rules(jobs, variables, project_dir:)
    kept = {}
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
      next unless result[:matched]
      next if result[:when] && result[:when].to_s == 'never'

      kept[name] = apply_rule_attributes(job_config, result)
    end

    cascade_drop_orphaned_needs(kept)
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
  def cascade_drop_orphaned_needs(job_configs)
    loop do
      surviving = job_configs.keys
      orphaned = job_configs.select do |_name, cfg|
        needs_job_names(cfg['needs']).any? { |n| !surviving.include?(n) && !n.include?('/') }
      end
      break if orphaned.empty?

      orphaned.each_key { |n| job_configs.delete(n) }
    end
    job_configs
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
