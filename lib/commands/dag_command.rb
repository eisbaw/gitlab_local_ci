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
require_relative '../pipeline_builder'

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

  # Error raised when the config cannot be resolved (PipelineBuilder errors:
  # missing file, invalid YAML, include or extends failure)
  class InvalidConfigError < StandardError; end

  # Error raised when workflow:rules create no pipeline, so there is no graph
  class NoPipelineError < StandardError; end

  # Initialize with options hash
  #
  # @param options [Hash] Command options
  # @option options [String] :entry Path to .gitlab-ci.yml (default: ./.gitlab-ci.yml)
  # @option options [String] :gitlab_dir Path to GitLab submodule (include:template)
  # @option options [String] :project, :pipeline, :variables see PipelineBuilder::Context
  def initialize(options = {})
    @entry = options[:entry] || './.gitlab-ci.yml'
    @context = PipelineBuilder::Context.from_options(
      options.merge(entry: @entry, gitlab_dir: options[:gitlab_dir] || './gitlab')
    )
  end

  # Execute the DAG command - main entry point
  #
  # Reads config, parses pipeline, validates DAG, generates DOT output
  # This is the orchestration method that composes simpler functions
  #
  # @return [String] Graphviz DOT format output
  # @raise [InvalidConfigError] if the config cannot be resolved
  # @raise [NoPipelineError] if workflow:rules create no pipeline
  # @raise [CircularDependencyError] if pipeline has circular dependencies
  def execute
    result = PipelineBuilder.build(@entry, @context)
    raise InvalidConfigError, result.errors.join("\n") unless result.ok?
    raise NoPipelineError, PipelineBuilder::WORKFLOW_SKIPPED_MESSAGE if result.workflow_skipped

    # Jobs of this pipeline context: rules decide (--pipeline, --variables)
    pipeline = build_pipeline_structure(result.stages, result.pipeline_jobs)
    validate_dag(pipeline)
    generate_dot(pipeline)
  end

  private

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
  # @param stages [Array<String>] Pipeline stages
  # @param job_configs [Hash] Job name => resolved job config (from PipelineBuilder)
  # @return [Hash] Structured pipeline representation
  def build_pipeline_structure(stages, job_configs)
    jobs = job_configs.to_h { |name, config| [name, build_job_structure(name, config, stages)] }
    { stages: stages, jobs: jobs }
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

    # Store full job config for tooltip generation
    # This is the concatenated/resolved YAML after anchors and extends
    full_config = job_config.dup

    {
      name: name,
      stage: stage,
      needs: needs,
      has_explicit_needs: has_explicit_needs,
      script: script,
      config: full_config
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
    lines << '  ranksep=2;'
    lines << '  compound=true;'
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

      # Add invisible anchor node for compound edges
      lines << "    __stage_anchor_#{sanitize_id(stage)} [style=invis, width=0, height=0];"
      lines << ''

      # Add nodes for jobs in this stage
      stage_jobs.each do |job|
        tooltip = generate_job_tooltip(job)
        lines << "    #{sanitize_id(job[:name])} [label=\"#{escape_label(job[:name])}\", tooltip=#{tooltip}];"
      end

      lines << '  }'
      lines << ''
    end

    # Generate edges for dependencies
    # Two types of dependencies:
    # 1. Explicit 'needs' dependencies (individual job edges)
    # 2. Implicit stage-based dependencies (stage cluster edges with ltail)
    edges = generate_dependency_edges(pipeline)

    # Assign colors to edges based on source node
    # All edges from the same source get the same color for visual clarity
    source_colors = assign_edge_colors(edges)

    edges.each do |edge|
      # Build edge attributes (ltail for compound edges, style for visual distinction, color by source)
      edge_attrs = []
      edge_attrs << "ltail=#{edge[:ltail]}" if edge[:ltail]
      edge_attrs << "lhead=#{edge[:lhead]}" if edge[:lhead]
      edge_attrs << "style=#{edge[:style]}" if edge[:style]
      edge_attrs << "color=\"#{source_colors[edge[:from]]}\"" if source_colors[edge[:from]]

      # Format edge with or without attributes
      attrs_str = edge_attrs.empty? ? '' : " [#{edge_attrs.join(', ')}]"
      lines << "  #{sanitize_id(edge[:from])} -> #{sanitize_id(edge[:to])}#{attrs_str};"
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
  # Visualization optimization:
  # - For implicit stage dependencies, draw single edge from previous stage cluster
  #   instead of individual edges from all jobs (reduces visual clutter)
  #
  # @param pipeline [Hash] Pipeline structure
  # @return [Array<Hash>] Array of edges with :from, :to, and optional :ltail keys
  def generate_dependency_edges(pipeline)
    edges = []
    stages = pipeline[:stages]
    jobs = pipeline[:jobs]
    # Same set generate_dot emits clusters (and anchors) for. Upstream skips
    # empty stages when ordering, so the implicit edge must too; an edge
    # from an empty stage would name a cluster that is never emitted.
    populated_stages = group_jobs_by_stage(pipeline).keys

    jobs.each_value do |job|
      if job[:has_explicit_needs]
        # Job has explicit needs - use those
        job[:needs].each do |dependency|
          edges << { from: dependency, to: job[:name] }
        end
      else
        # Job has no explicit needs - add implicit stage dependency
        # Instead of drawing edges from all previous jobs, draw a single edge
        # from the nearest earlier stage cluster that has jobs (using
        # compound graph ltail)
        previous_stage = nearest_populated_stage_before(job[:stage], stages, populated_stages)
        next unless previous_stage

        # Create stage-level edge using invisible anchor and ltail attribute
        # This makes the edge appear to come from the entire stage cluster
        edges << {
          from: "__stage_anchor_#{sanitize_id(previous_stage)}",
          to: job[:name],
          ltail: "cluster_#{sanitize_id(previous_stage)}",
          style: 'bold'
        }
      end
    end

    edges
  end

  # @param stage [String] the job's stage
  # @param stages [Array<String>] pipeline stages in order
  # @param populated_stages [Array<String>] stages that have at least one job
  # @return [String, nil] the last stage before +stage+ that has jobs; nil
  #   when +stage+ is unknown or every earlier stage is empty
  def nearest_populated_stage_before(stage, stages, populated_stages)
    stage_index = stages.index(stage)
    return nil unless stage_index

    stages.take(stage_index).reverse.find { |earlier| populated_stages.include?(earlier) }
  end

  # Assign colors to edges based on source node
  #
  # All edges from the same source node get the same color for visual clarity.
  # Uses a palette of visually distinct colors that work well in Graphviz.
  #
  # @param edges [Array<Hash>] Array of edge hashes with :from keys
  # @return [Hash{String => String}] Map of source node to color
  def assign_edge_colors(edges)
    # Palette of visually distinct colors (ColorBrewer Set1 + Set2)
    # These colors are chosen to be distinguishable and work well in DAG visualizations
    color_palette = %w[
      #E41A1C #377EB8 #4DAF4A #984EA3 #FF7F00
      #FFFF33 #A65628 #F781BF #8DD3C7 #FFFFB3
      #BEBADA #FB8072 #80B1D3 #FDB462 #B3DE69
      #FCCDE5 #D9D9D9 #BC80BD #CCEBC5 #FFED6F
    ]

    # Collect all unique source nodes
    source_nodes = edges.map { |edge| edge[:from] }.uniq.sort

    # Assign colors to source nodes, cycling through palette if needed
    source_colors = {}
    source_nodes.each_with_index do |source, index|
      source_colors[source] = color_palette[index % color_palette.length]
    end

    source_colors
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

  # Generate tooltip for a job showing the resolved YAML configuration
  #
  # This shows the "concatenated" YAML - the full job configuration after
  # anchors and extends have been resolved by YAML parser
  #
  # @param job [Hash] Job structure with :config key
  # @return [String] Quoted and escaped tooltip string for DOT format
  def generate_job_tooltip(job)
    return '""' unless job[:config]

    # Convert config hash to YAML, pretty-printed
    yaml_str = YAML.dump(job[:config])

    # Escape for DOT tooltip attribute
    # - Replace backslashes with double backslashes
    # - Replace quotes with escaped quotes
    # - Replace newlines with \n literal
    escaped = yaml_str.gsub('\\', '\\\\\\\\')
                      .gsub('"', '\\"')
                      .gsub("\n", '\\n')

    # Return as quoted string
    "\"#{escaped}\""
  end
end
