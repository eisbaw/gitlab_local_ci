# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require_relative 'ci_keywords'

# `parallel:` expansion, upstream Config::Normalizer (NumberStrategy,
# MatrixStrategy) and Interpolation::MatrixInterpolator, plus the
# validation of Entry::Product::{Parallel,Matrix,Variables} it relies on.
#
# Upstream runs it on the composed jobs (Config#normalized_jobs, after
# default:/inherit:), before YamlProcessor's stage/needs checks and before
# any rules, so rules evaluate per instance. PipelineBuilder calls it at
# that point.
#
# An instance is the job's config with:
#   variables  the job's `variables:` with the matrix variables over them
#              (upstream deep-merges them into job_variables, so they rank
#              as job yaml variables: rules:variables and CLI still win)
#   parallel   { 'instance' => i, 'total' => n } (1-based), the normalized
#              form CI_NODE_INDEX/CI_NODE_TOTAL derive from
#              (PipelineBuilder.parallel_instance)
# Only visible jobs are expanded; hidden templates are not jobs.
module ParallelExpander
  # Upstream Entry::Product::Parallel::PARALLEL_LIMIT.
  PARALLEL_LIMIT = 200

  # Upstream MatrixInterpolator::MATRIX_EXPRESSION_REGEXP.
  MATRIX_EXPRESSION = /\$\[\[\s*matrix\.([a-zA-Z0-9_-]+)\s*\]\]/

  # Keys of a need on another pipeline's job (Entry::Need
  # CrossPipelineDependency, EE CrossProjectDependency): not fanned out.
  CROSS_PIPELINE_NEED_KEYS = %w[project pipeline ref].freeze

  # One job a parallel job expands to. variables: matrix variables,
  # String => String, config order; empty for parallel: N.
  Instance = Struct.new(:name, :index, :total, :variables, keyword_init: true)

  module_function

  # Entry::Product::Parallel errors of every visible job's `parallel:`
  # and of its needs' `parallel:` (Entry::Needs/Need: matrix only), in
  # upstream lint's wording. Expansion assumes these are empty.
  #
  # @param jobs [Hash] name => job, composed
  # @return [Array<String>]
  def errors(jobs)
    jobs.flat_map do |name, job|
      next [] if CiKeywords.hidden?(name) || !job.is_a?(Hash)

      own = job['parallel'].nil? ? [] : parallel_errors("jobs:#{name}:parallel", job['parallel'])
      own + needs_parallel_errors(name, needs_parallel(job['needs']))
    end
  end

  # Entry::Needs rejects a number once for the whole list (and composes no
  # Need then); otherwise each Need's matrix is checked.
  def needs_parallel_errors(name, parallels)
    return ["jobs:#{name}:needs config cannot use \"parallel: <number>\"."] if parallels.any?(Numeric)

    parallels.flat_map { |parallel| parallel_errors("jobs:#{name}:needs:need:parallel", parallel) }
  end

  # `parallel:` values of the map-form needs that have one.
  def needs_parallel(needs)
    return [] unless needs.is_a?(Array)

    needs.filter_map { |need| need['parallel'] if need.is_a?(Hash) && !need['parallel'].nil? }
  end

  # Entry::Product::Parallel: an Integer (ParallelBuilds) or a Hash
  # (MatrixBuilds); a Float is numeric and fails only_integer.
  def parallel_errors(location, parallel)
    case parallel
    when Integer, Float
      return ["#{location} config must be an integer"] unless parallel.is_a?(Integer)
      return ["#{location} config must be greater than or equal to 1"] if parallel < 1
      return ["#{location} config must be less than or equal to #{PARALLEL_LIMIT}"] if parallel > PARALLEL_LIMIT

      []
    when Hash
      unknown = parallel.keys - ['matrix']
      errors = []
      errors << "#{location} config contains unknown keys: #{unknown.join(', ')}" unless unknown.empty?
      return errors << "#{location} config missing required keys: matrix" unless parallel.key?('matrix')

      errors + matrix_errors("#{location}:matrix", parallel['matrix'])
    else
      ["#{location} should be an integer or a hash"]
    end
  end

  # Entry::Product::Matrix and its Variables entries (location
  # "...:matrix:variables": the entries have no key, so upstream names them
  # after the class).
  def matrix_errors(location, matrix)
    return ["#{location} config should be an array of hashes"] unless matrix.is_a?(Array) && matrix.all?(Hash)

    errors = matrix.flat_map { |variables| matrix_variables_errors("#{location}:variables", variables) }.uniq
    return errors unless errors.empty?

    generated = matrix.sum { |variables| variables.values.reduce(1) { |product, value| product * Array(value).size } }
    return ["#{location} config generates too many jobs (maximum is #{PARALLEL_LIMIT})"] if generated > PARALLEL_LIMIT

    []
  end

  # Entry::Product::Variables: `variables: { array_values: true }`
  # (LegacyValidationHelpers#validate_array_value_variables) and at least
  # one key. YAML gives no Symbols, so alphanumeric is String or Integer: a
  # Float (`3.10`), a boolean or a nested list is invalid, as upstream.
  def matrix_variables_errors(location, variables)
    alphanumeric = ->(value) { value.is_a?(String) || value.is_a?(Integer) }
    errors = []
    valid = variables.keys.all?(&alphanumeric) && variables.values.none?(&:nil?) &&
            variables.values.flatten(1).all?(&alphanumeric)
    errors << "#{location} config should be a hash of key value pairs, value can be an array" unless valid
    errors << "#{location} config requires at least 1 items" if variables.empty?
    errors
  end

  # The instances of a job, upstream Normalizer::Factory: NumberStrategy
  # ("name i/n") or MatrixStrategy ("name: [v1, v2]", each matrix entry's
  # combinations in key order, entries in order). `parallel` must be valid
  # (errors); `matrix: []` gives no instance, so the job vanishes, as
  # upstream.
  #
  # @return [Array<Instance>]
  def instances(job_name, parallel)
    if parallel.is_a?(Integer)
      return Array.new(parallel) { |i| Instance.new(name: "#{job_name} #{i + 1}/#{parallel}", index: i + 1, total: parallel, variables: {}) }
    end
    raise ArgumentError, "#{job_name}: parallel must be validated first, got #{parallel.inspect}" unless parallel.is_a?(Hash) && parallel['matrix'].is_a?(Array)

    combinations = matrix_combinations(parallel['matrix'])
    combinations.each_with_index.map do |variables, i|
      Instance.new(name: "#{job_name}: [#{variables.values.join(', ')}]", index: i + 1, total: combinations.size,
                   variables: variables)
    end
  end

  # MatrixStrategy.expand over Product::Variables#value (keys and values
  # to_s, a scalar value is a one-element list).
  #
  # @return [Array<Hash>] String => String per instance
  def matrix_combinations(matrix)
    matrix.flat_map do |entry|
      keys = entry.keys.map(&:to_s)
      values = entry.values.map { |value| Array(value).map(&:to_s) }
      values[0].product(*values.drop(1)).map { |combination| keys.zip(combination).to_h }
    end
  end

  # Upstream Normalizer#normalize_jobs: every visible parallel job
  # replaced, in place, by its instances; then in every visible job
  # (instances included) `$[[ matrix.X ]]` in needs interpolated, and
  # needs/dependencies on a parallel job fanned out to its instances (or
  # to the instances needs:parallel:matrix names).
  #
  # @param jobs [Hash] name => job, composed, errors(jobs) empty
  # @return [Array(Hash, Array<String>)] [expanded jobs, errors]; errors
  #   are upstream's normalizer errors, joined into one as YamlProcessor
  #   reports them
  def expand(jobs)
    parallelized = jobs.each_with_object({}) do |(name, job), acc|
      next if CiKeywords.hidden?(name) || !job.is_a?(Hash) || job['parallel'].nil?

      acc[name] = instances(name, job['parallel'])
    end

    errors = []
    expanded = {}
    jobs.each do |name, job|
      if CiKeywords.hidden?(name) || !job.is_a?(Hash)
        expanded[name] = job
      elsif (instances = parallelized[name])
        instances.each do |instance|
          expanded[instance.name] = normalize_job(name, instance_job(job, instance), instance.variables, parallelized, errors)
        end
      else
        expanded[name] = normalize_job(name, job, {}, parallelized, errors)
      end
    end
    [expanded, errors.empty? ? [] : [errors.uniq.join(', ')]]
  end

  # The job's config for one instance (module comment).
  def instance_job(job, instance)
    instance_job = job.merge('parallel' => { 'instance' => instance.index, 'total' => instance.total })
    return instance_job if instance.variables.empty?

    own = job['variables']
    # A non-Hash `variables:` is invalid; left for JobEnvironment to report.
    return instance_job unless own.nil? || own.is_a?(Hash)

    instance_job.merge('variables' => (own || {}).merge(instance.variables))
  end

  # Upstream Normalizer#normalize_job. Interpolation sees the matrix
  # variables only (upstream passes all job variables, but a non-matrix
  # one is a {value:} hash there and would interpolate as its inspect
  # text); a failed interpolation leaves the needs as written.
  def normalize_job(name, job, matrix_variables, parallelized, errors)
    job = job.dup
    if job['needs'].is_a?(Array)
      interpolation_errors = []
      interpolated = interpolate(job['needs'], matrix_variables, interpolation_errors)
      if interpolation_errors.empty?
        job['needs'] = interpolated
      else
        errors.concat(interpolation_errors.map { |error| "#{name} job: #{error}" })
      end
      job['needs'] = fan_out_needs(job['needs'], parallelized)
    end
    job['dependencies'] = fan_out_dependencies(job['dependencies'], parallelized) if job['dependencies'].is_a?(Array)
    job
  end

  # MatrixInterpolator#interpolate_value: every String in the needs tree.
  def interpolate(value, variables, errors)
    case value
    when String
      value.scan(MATRIX_EXPRESSION).map(&:first).uniq.reduce(value) do |result, variable|
        # Block form: a value is literal text, never a back-reference.
        next result.gsub(/\$\[\[\s*matrix\.#{Regexp.escape(variable)}\s*\]\]/) { variables[variable] } if variables.key?(variable)

        errors << "'#{variable}' does not exist in matrix configuration"
        result
      end
    when Hash then value.transform_values { |item| interpolate(item, variables, errors) }
    when Array then value.map { |item| interpolate(item, variables, errors) }
    else value
    end
  end

  # Normalizer#expand_parallelized_job_names.
  def fan_out_dependencies(dependencies, parallelized)
    dependencies.flat_map { |name| parallelized[name]&.map(&:name) || [name] }
  end

  # Normalizer#expand_parallelized_needs, over the needs as written: a
  # String stays a String, a {job:} need keeps its other keys and loses
  # `parallel:`. needs:parallel:matrix names instances by generating them
  # from its own matrix (a combination the job does not have stays, and is
  # an undefined need). Cross-pipeline needs and needs on a non-parallel
  # job are untouched.
  def fan_out_needs(needs, parallelized)
    needs.flat_map do |need|
      next [need] if need.is_a?(Hash) && CROSS_PIPELINE_NEED_KEYS.any? { |key| need.key?(key) }

      name = need.is_a?(Hash) ? need['job'] : need
      next [need] unless (instances = parallelized[name])

      if need.is_a?(Hash)
        instances = instances(name, need['parallel']) unless need['parallel'].nil?
        instances.map { |instance| need.except('parallel').merge('job' => instance.name) }
      else
        instances.map(&:name)
      end
    end
  end
end
