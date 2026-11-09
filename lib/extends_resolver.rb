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

require_relative 'config_merge'
require_relative 'ci_keywords'

# Resolves 'extends' directives in GitLab CI configuration
#
# Mirrors upstream Extendable::Entry#extend! (gitlab/ submodule): parents are
# resolved recursively, deep-merged in `extends:` order (later parent wins),
# then the job's own keys are merged on top. The merge is ConfigMerge, the
# same one includes use: hashes merge, arrays replace.
class ExtendsResolver
  NestingTooDeepError = Class.new(StandardError)

  # Upstream Extendable::Entry::MAX_NESTING_LEVELS: an entry with more than
  # this many ancestors may not itself extend, i.e. 11 levels are allowed.
  MAX_NESTING_LEVELS = 10

  # Resolve all extends directives in a configuration
  #
  # @param config [Hash] The GitLab CI configuration
  # @return [Hash] Configuration with extends resolved
  def resolve_extends(config)
    # Separate jobs and templates
    jobs = {}
    templates = {}

    config.each do |key, value|
      next unless CiKeywords.job_entry?(key, value)

      if CiKeywords.hidden?(key)
        templates[key] = value
      else
        jobs[key] = value
      end
    end

    # Resolve extends for all jobs
    resolved_jobs = {}
    jobs.each do |job_name, job_config|
      resolved_jobs[job_name] = resolve_job_extends(job_name, job_config, jobs, templates, [])
    end

    # Jobs move after globals/templates here; upstream keeps positions
    # (TASK-31).
    config.reject { |key, _| jobs.key?(key) }.merge(resolved_jobs)
  end

  private

  # @param job_name [String] Name of the job or template being resolved
  # @param job_config [Hash] Its unresolved configuration
  # @param jobs [Hash] All jobs in config
  # @param templates [Hash] All hidden (.) templates
  # @param ancestors [Array<String>] Entries that extend (transitively) into this one
  # @return [Hash] Resolved configuration without the extends key
  def resolve_job_extends(job_name, job_config, jobs, templates, ancestors)
    return ConfigMerge.deep_dup(job_config) unless job_config.key?('extends')

    # Same check order as upstream Entry#extend! (unknown, too deep, circular);
    # only the nesting message is upstream-verbatim.
    parent_names = Array(job_config['extends']).map(&:to_s)
    unknown = parent_names.reject { |name| templates.key?(name) || jobs.key?(name) }
    unless unknown.empty?
      raise "Job '#{job_name}' extends from '#{unknown.first}' but '#{unknown.first}' is not defined"
    end
    raise NestingTooDeepError, "#{job_name}: nesting too deep in `extends`" if ancestors.size > MAX_NESTING_LEVELS
    if ancestors.include?(job_name)
      raise "Circular extends dependency detected: #{job_name} is part of a circular chain"
    end

    merged = parent_names.reduce({}) do |acc, parent_name|
      parent_config = templates[parent_name] || jobs[parent_name]
      ConfigMerge.deep_merge(acc, resolve_job_extends(parent_name, parent_config, jobs, templates, ancestors + [job_name]))
    end

    result = ConfigMerge.deep_merge(merged, job_config)
    result.delete('extends')
    result
  end
end
