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

require 'yaml'
require 'json'

# DagCommand generates Graphviz DOT format visualizations of GitLab CI pipeline DAG
#
# This is a pure data transformation: pipeline configuration → DOT string
# No side effects, no state mutation - just input transformation to output
#
# Design principles:
# - Simple data transformation (YAML → internal structure → DOT)
# - Pure function approach where possible
# - Fail-fast on errors with clear context
# - Single responsibility: parse config and generate DOT
# - No business logic in output - just data formatting
class DagCommand
  # Error raised when circular dependencies detected in DAG
  class CircularDependencyError < StandardError; end

  # Error raised when invalid YAML configuration
  class InvalidConfigError < StandardError; end

  # Error raised when configuration file not found
  class FileNotFoundError < StandardError; end

  # Initialize with options hash
  #
  # @param options [Hash] Command options
  # @option options [String] :entry Path to .gitlab-ci.yml (default: ./.gitlab-ci.yml)
  # @option options [String] :gitlab_dir Path to GitLab submodule (future use)
  def initialize(options = {})
    @entry = options[:entry] || './.gitlab-ci.yml'
    @gitlab_dir = options[:gitlab_dir] || './gitlab'
  end

  # Execute the DAG command - main entry point
  #
  # Reads config, parses pipeline, validates DAG, generates DOT output
  # This is the orchestration method that composes simpler functions
  #
  # @return [String] Graphviz DOT format output
  # @raise [FileNotFoundError] if config file doesn't exist
  # @raise [InvalidConfigError] if YAML is malformed
  # @raise [CircularDependencyError] if pipeline has circular dependencies
  def execute
    config_content = read_config_file(@entry)
    config = parse_yaml(config_content)
    pipeline = build_pipeline_structure(config)
    validate_dag(pipeline)
    generate_dot(pipeline)
  end

  private

  # Read configuration file from filesystem
  #
  # @param file_path [String] Path to config file
  # @return [String] File contents
  # @raise [FileNotFoundError] if file doesn't exist
  def read_config_file(file_path)
    File.read(file_path)
  rescue Errno::ENOENT
    raise FileNotFoundError, "Configuration file not found: #{file_path}"
  rescue Errno::EACCES => e
    raise FileNotFoundError, "Cannot read configuration file: #{file_path} - #{e.message}"
  end

  # Parse YAML configuration
  #
  # @param content [String] YAML content
  # @return [Hash] Parsed configuration
  # @raise [InvalidConfigError] if YAML is malformed
  def parse_yaml(content)
    YAML.safe_load(content, permitted_classes: [Symbol], aliases: true)
  rescue Psych::SyntaxError => e
    raise InvalidConfigError, "Invalid YAML syntax: #{e.message}"
  rescue StandardError => e
    raise InvalidConfigError, "Failed to parse YAML: #{e.message}"
  end

  # Build internal pipeline structure from parsed config
  #
  # This transforms the YAML hash into a structured representation
  # that's easier to work with for DAG generation
  #
  # Data structure:
  # {
  #   stages: ["build", "test", "deploy"],
  #   jobs: {
  #     "job-name" => {
  #       name: "job-name",
  #       stage: "test",
  #       needs: ["build-job"],
  #       script: ["echo hello"]
  #     }
  #   }
  # }
  #
  # @param config [Hash] Parsed YAML configuration
  # @return [Hash] Structured pipeline representation
  def build_pipeline_structure(config)
    # Extract stages (default to standard GitLab stages if not specified)
    stages = config['stages'] || %w[build test deploy]

    # Build job map - filter out non-job keys (stages, variables, etc.)
    jobs = {}
    config.each do |key, value|
      next if reserved_key?(key)
      next unless value.is_a?(Hash)

      jobs[key] = build_job_structure(key, value, stages)
    end

    { stages: stages, jobs: jobs }
  end

  # Check if a key is a reserved GitLab CI keyword (not a job name)
  #
  # @param key [String] Configuration key
  # @return [Boolean] true if reserved keyword
  def reserved_key?(key)
    %w[
      stages variables include default workflow
      before_script after_script cache
    ].include?(key)
  end

  # Build structured representation of a single job
  #
  # @param name [String] Job name
  # @param job_config [Hash] Job configuration from YAML
  # @param stages [Array<String>] Available stages
  # @return [Hash] Structured job data
  def build_job_structure(name, job_config, stages)
    # Determine job stage - default to 'test' if not specified
    stage = job_config['stage'] || 'test'

    # Extract needs dependencies
    # Important: we need to track whether 'needs' was explicitly set
    # to differentiate between:
    # - No needs key (nil) -> implicit stage dependencies
    # - needs: [] -> explicit empty dependencies
    # - needs: [jobs] -> explicit dependencies
    needs = extract_needs(job_config['needs'])
    has_explicit_needs = job_config.key?('needs')

    # Extract script (required for actual jobs, but we're just visualizing)
    script = job_config['script'] || []

    {
      name: name,
      stage: stage,
      needs: needs,
      has_explicit_needs: has_explicit_needs,
      script: script
    }
  end

  # Extract and normalize 'needs' dependencies
  #
  # GitLab supports multiple formats:
  # - needs: [job1, job2]
  # - needs:
  #     - job: job1
  #     - job: job2
  #       artifacts: true
  #
  # We normalize to simple array of job names
  #
  # @param needs_config [Array, nil] Raw needs configuration
  # @return [Array<String>] Normalized job names
  def extract_needs(needs_config)
    return [] if needs_config.nil?
    return [] unless needs_config.is_a?(Array)

    needs_config.map do |need|
      case need
      when String
        need
      when Hash
        need['job'] || need[:job]
      else
        nil
      end
    end.compact
  end

  # Validate DAG for circular dependencies
  #
  # Uses depth-first search to detect cycles
  # This is the fail-fast validation step
  #
  # @param pipeline [Hash] Pipeline structure
  # @raise [CircularDependencyError] if circular dependency detected
  def validate_dag(pipeline)
    # Build adjacency list for DFS
    jobs = pipeline[:jobs]

    # Track visited nodes and recursion stack
    visited = {}
    rec_stack = {}

    # Check each job for cycles
    jobs.each_key do |job_name|
      next if visited[job_name]

      if has_cycle?(job_name, jobs, visited, rec_stack)
        raise CircularDependencyError,
              "Circular dependency detected involving job: #{job_name}"
      end
    end
  end

  # Detect cycle using DFS
  #
  # @param job_name [String] Current job being checked
  # @param jobs [Hash] All jobs in pipeline
  # @param visited [Hash] Tracking of visited nodes
  # @param rec_stack [Hash] Tracking of recursion stack for cycle detection
  # @return [Boolean] true if cycle detected
  def has_cycle?(job_name, jobs, visited, rec_stack)
    visited[job_name] = true
    rec_stack[job_name] = true

    job = jobs[job_name]
    return false unless job

    # Check all dependencies
    job[:needs].each do |dependency|
      next unless jobs[dependency]

      if !visited[dependency]
        return true if has_cycle?(dependency, jobs, visited, rec_stack)
      elsif rec_stack[dependency]
        # Found a back edge - cycle detected
        return true
      end
    end

    # Remove from recursion stack before returning
    rec_stack[job_name] = false
    false
  end

  # Generate Graphviz DOT format output
  #
  # This is a pure transformation: pipeline structure → DOT string
  # No side effects - just string building
  #
  # Output structure:
  # - digraph with LR (left-to-right) layout
  # - subgraph clusters for stages
  # - nodes for jobs
  # - directed edges for needs dependencies
  #
  # @param pipeline [Hash] Pipeline structure
  # @return [String] DOT format output
  def generate_dot(pipeline)
    lines = []
    lines << 'digraph pipeline {'
    lines << '  rankdir="LR";'
    lines << '  node [shape=box, style=filled, fillcolor=lightblue];'
    lines << ''

    # Group jobs by stage for subgraph clusters
    jobs_by_stage = group_jobs_by_stage(pipeline)

    # Generate subgraph for each stage
    pipeline[:stages].each do |stage|
      stage_jobs = jobs_by_stage[stage] || []
      next if stage_jobs.empty?

      lines << "  subgraph cluster_#{sanitize_id(stage)} {"
      lines << "    label=\"#{escape_label(stage)}\";"
      lines << "    style=filled;"
      lines << "    fillcolor=lightgrey;"
      lines << ''

      # Add nodes for jobs in this stage
      stage_jobs.each do |job|
        lines << "    #{sanitize_id(job[:name])} [label=\"#{escape_label(job[:name])}\"];"
      end

      lines << '  }'
      lines << ''
    end

    # Generate edges for dependencies
    # Two types of dependencies:
    # 1. Explicit 'needs' dependencies
    # 2. Implicit stage-based dependencies (for jobs without 'needs')
    edges = generate_dependency_edges(pipeline)
    edges.each do |edge|
      lines << "  #{sanitize_id(edge[:from])} -> #{sanitize_id(edge[:to])};"
    end

    lines << '}'
    lines.join("\n")
  end

  # Generate dependency edges based on both explicit needs and implicit stage ordering
  #
  # GitLab CI/CD behavior:
  # - Jobs with explicit 'needs' only depend on those specified jobs
  # - Jobs without 'needs' implicitly depend on all jobs in previous stages
  # - Jobs with 'needs: []' have no dependencies
  #
  # @param pipeline [Hash] Pipeline structure
  # @return [Array<Hash>] Array of edges with :from and :to keys
  def generate_dependency_edges(pipeline)
    edges = []
    stages = pipeline[:stages]
    jobs = pipeline[:jobs]

    jobs.each_value do |job|
      if job[:has_explicit_needs]
        # Job has explicit needs - use those
        job[:needs].each do |dependency|
          edges << { from: dependency, to: job[:name] }
        end
      else
        # Job has no explicit needs - add implicit stage dependencies
        # Find all jobs in previous stages
        job_stage_index = stages.index(job[:stage])
        next unless job_stage_index && job_stage_index > 0

        # Get all previous stages
        previous_stages = stages[0...job_stage_index]

        # Find all jobs in those previous stages
        previous_stage_jobs = jobs.values.select do |other_job|
          previous_stages.include?(other_job[:stage])
        end

        # Create edges from all previous stage jobs to this job
        previous_stage_jobs.each do |prev_job|
          edges << { from: prev_job[:name], to: job[:name] }
        end
      end
    end

    edges
  end

  # Group jobs by their stage
  #
  # @param pipeline [Hash] Pipeline structure
  # @return [Hash{String => Array<Hash>}] Jobs grouped by stage name
  def group_jobs_by_stage(pipeline)
    pipeline[:jobs].each_value.group_by { |job| job[:stage] }
  end

  # Sanitize identifier for DOT format
  #
  # Replace characters that are problematic in DOT identifiers
  #
  # @param str [String] Input string
  # @return [String] Sanitized identifier
  def sanitize_id(str)
    str.gsub(/[^a-zA-Z0-9_]/, '_')
  end

  # Escape label for DOT format
  #
  # Escape quotes and backslashes in labels
  #
  # @param str [String] Input string
  # @return [String] Escaped label
  def escape_label(str)
    str.gsub('\\', '\\\\').gsub('"', '\\"')
  end
end
