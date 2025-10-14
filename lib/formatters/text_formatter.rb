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

require_relative 'base_formatter'

module Formatters
  # Formats output as human-readable text
  # Default formatter for terminal output
  class TextFormatter < BaseFormatter
    # Format data as human-readable text
    #
    # @param data [Hash] Data to format
    # @param command [Symbol] The command type
    # @return [String] Formatted text output
    def format(data, command:)
      case command
      when :lint
        format_lint(data)
      when :dag
        format_dag(data)
      when :dry_run
        format_dry_run(data)
      else
        raise ArgumentError, "Unknown command: #{command}"
      end
    end

    private

    # Format lint command results
    #
    # @param data [Hash] Lint results
    # @return [String] Formatted text
    def format_lint(data)
      validate_data(data, [:valid])

      output = []

      if data[:valid]
        output << "GitLab CI configuration is valid"

        if data[:stages]
          stages_list = Array(data[:stages]).join(', ')
          output << "Stages: #{stages_list}"
        end

        if data[:jobs]
          job_count = Array(data[:jobs]).size
          output << "Jobs: #{job_count}"
        end
      else
        output << "GitLab CI configuration is invalid"

        if data[:errors] && !data[:errors].empty?
          output << "Errors:"
          Array(data[:errors]).each do |error|
            output << "  - #{error}"
          end
        end
      end

      output.join("\n")
    end

    # Format DAG command results
    #
    # @param data [Hash] DAG structure
    # @return [String] Formatted text (Graphviz DOT format)
    def format_dag(data)
      validate_data(data, [:stages, :jobs])

      output = []
      output << "digraph pipeline {"
      output << "  rankdir=LR;"
      output << ""

      # Create subgraph clusters for each stage
      stages = Array(data[:stages])
      stages.each do |stage|
        stage_name = sanitize_dot_identifier(stage)
        output << "  subgraph cluster_#{stage_name} {"
        output << "    label=\"#{stage}\";"

        # Add jobs belonging to this stage
        jobs = Array(data[:jobs])
        jobs.each do |job|
          job_stage = job[:stage] || job['stage']
          if job_stage == stage
            job_name = sanitize_dot_identifier(job[:name] || job['name'])
            output << "    #{job_name};"
          end
        end

        output << "  }"
      end

      # Add edges for needs dependencies
      output << ""
      dependencies = Array(data[:dependencies])
      dependencies.each do |dep|
        from = sanitize_dot_identifier(dep[:from] || dep['from'])
        to = sanitize_dot_identifier(dep[:to] || dep['to'])
        output << "  #{from} -> #{to};"
      end

      output << "}"
      output.join("\n")
    end

    # Sanitize identifier for DOT format
    #
    # @param str [String] Identifier to sanitize
    # @return [String] Sanitized identifier
    def sanitize_dot_identifier(str)
      str.to_s.gsub(/[^a-zA-Z0-9_]/, '_')
    end

    # Format dry-run command results
    #
    # @param data [Hash] Dry-run simulation results
    # @return [String] Formatted text
    def format_dry_run(data)
      validate_data(data, [:pipeline_id, :status])

      output = []

      # Header with pipeline info
      pipeline_id = data[:pipeline_id]
      job_count = Array(data[:jobs]).size
      output << "Pipeline ##{pipeline_id} created with #{job_count} jobs"
      output << ""

      # Events timeline
      events = Array(data[:events])
      events.each do |event|
        timestamp = event[:timestamp] || event['timestamp'] || 0
        event_type = event[:type] || event['type']
        job_name = event[:job_name] || event['job_name']
        runner_id = event[:runner_id] || event['runner_id']
        status = event[:status] || event['status']

        case event_type.to_s
        when 'job_assigned'
          output << "[#{timestamp}s] Job '#{job_name}' assigned to #{runner_id}"
        when 'job_started'
          output << "[#{timestamp}s] Job '#{job_name}' started"
        when 'job_completed'
          output << "[#{timestamp}s] Job '#{job_name}' completed (#{status})"
        when 'job_waiting'
          reason = event[:reason] || event['reason'] || 'no eligible runner'
          output << "[#{timestamp}s] Job '#{job_name}' waiting (#{reason})"
        else
          output << "[#{timestamp}s] #{event_type}: #{job_name}"
        end
      end

      # Final status
      output << ""
      output << "Pipeline completed: #{data[:status]}"

      output.join("\n")
    end
  end
end
