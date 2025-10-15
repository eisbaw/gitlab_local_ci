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

require 'set'

# Resolves 'extends' directives in GitLab CI configuration
#
# Handles inheritance from templates (jobs starting with .)
# Supports both single extends (string) and multiple extends (array)
#
# MPED Principles:
# - Fail-fast: Detects circular dependencies immediately
# - Explicit: Clear error messages for missing parents
# - Simple: Resolves in topological order (bottom-up)
class ExtendsResolver
  # Keys that are merged (concatenated) rather than replaced
  MERGE_KEYS = %w[
    before_script
    after_script
    cache
    tags
    dependencies
    needs
  ].freeze

  # Keys in artifacts that are merged
  ARTIFACTS_MERGE_KEYS = %w[
    paths
    reports
  ].freeze

  # Resolve all extends directives in a configuration
  #
  # @param config [Hash] The GitLab CI configuration
  # @return [Hash] Configuration with extends resolved
  def resolve_extends(config)
    # Separate jobs and templates
    jobs = {}
    templates = {}

    config.each do |key, value|
      next unless value.is_a?(Hash)

      if key.start_with?('.')
        templates[key] = value
      elsif !%w[stages variables workflow include default].include?(key)
        jobs[key] = value
      end
    end

    # Resolve extends for all jobs
    resolved_jobs = {}
    jobs.each do |job_name, job_config|
      resolved_jobs[job_name] = resolve_job_extends(job_name, job_config, jobs, templates, Set.new)
    end

    # Build result with resolved jobs
    result = config.reject { |key, value| value.is_a?(Hash) && !key.start_with?('.') && !%w[stages variables workflow include default].include?(key) }
    result.merge(resolved_jobs)
  end

  private

  # Resolve extends for a single job
  #
  # @param job_name [String] Name of the job
  # @param job_config [Hash] Job configuration
  # @param jobs [Hash] All jobs in config
  # @param templates [Hash] All template definitions
  # @param visited [Set] Set of visited job names (for circular detection)
  # @return [Hash] Resolved job configuration
  def resolve_job_extends(job_name, job_config, jobs, templates, visited)
    # Base case: no extends
    return job_config.dup unless job_config.key?('extends')

    # Circular dependency detection
    if visited.include?(job_name)
      raise "Circular extends dependency detected: #{job_name} is part of a circular chain"
    end

    visited.add(job_name)

    begin
      # Get extends directive (can be string or array)
      extends_value = job_config['extends']
      parent_names = extends_value.is_a?(Array) ? extends_value : [extends_value]

      # Start with empty base, will merge parents left-to-right
      merged = {}

      # Merge each parent in order
      parent_names.each do |parent_name|
        # Find parent (check both jobs and templates)
        parent_config = templates[parent_name] || jobs[parent_name]

        unless parent_config
          raise "Job '#{job_name}' extends from '#{parent_name}' but '#{parent_name}' is not defined"
        end

        # Recursively resolve parent's extends
        resolved_parent = resolve_job_extends(parent_name, parent_config, jobs, templates, visited.dup)

        # Merge parent into result
        merged = merge_job_config(merged, resolved_parent)
      end

      # Finally, merge the job's own config (overrides parents)
      result = merge_job_config(merged, job_config)

      # Remove extends key from result
      result.delete('extends')

      result
    ensure
      visited.delete(job_name)
    end
  end

  # Merge two job configurations with GitLab semantics
  #
  # @param base [Hash] Base configuration
  # @param overlay [Hash] Configuration to merge on top
  # @return [Hash] Merged configuration
  def merge_job_config(base, overlay)
    result = base.dup

    overlay.each do |key, value|
      if key == 'extends'
        # Skip extends key - we're resolving it
        next
      elsif key == 'variables'
        # Variables are deep-merged
        result[key] = merge_variables(result[key] || {}, value)
      elsif key == 'artifacts' && value.is_a?(Hash)
        # Artifacts has special merge logic
        result[key] = merge_artifacts(result[key] || {}, value)
      elsif MERGE_KEYS.include?(key) && value.is_a?(Array)
        # These keys are concatenated (array merge)
        base_array = result[key] || []
        result[key] = base_array + value
      elsif result[key].is_a?(Hash) && value.is_a?(Hash)
        # Nested hashes are recursively merged
        result[key] = merge_job_config(result[key], value)
      else
        # Everything else: overlay replaces base
        result[key] = deep_dup(value)
      end
    end

    result
  end

  # Merge variables (deep merge)
  #
  # @param base [Hash] Base variables
  # @param overlay [Hash] Variables to merge on top
  # @return [Hash] Merged variables
  def merge_variables(base, overlay)
    result = base.dup
    overlay.each do |key, value|
      result[key] = value
    end
    result
  end

  # Merge artifacts with special handling for paths and reports
  #
  # @param base [Hash] Base artifacts config
  # @param overlay [Hash] Artifacts config to merge on top
  # @return [Hash] Merged artifacts config
  def merge_artifacts(base, overlay)
    result = base.dup

    overlay.each do |key, value|
      if ARTIFACTS_MERGE_KEYS.include?(key) && value.is_a?(Array)
        # Paths and reports are concatenated
        base_array = result[key] || []
        result[key] = base_array + value
      else
        # Other artifact keys are replaced
        result[key] = deep_dup(value)
      end
    end

    result
  end

  # Deep duplicate a value (handles nested arrays/hashes)
  #
  # @param value [Object] Value to duplicate
  # @return [Object] Deep copy of value
  def deep_dup(value)
    case value
    when Hash
      value.transform_values { |v| deep_dup(v) }
    when Array
      value.map { |v| deep_dup(v) }
    else
      value.dup rescue value
    end
  end
end
