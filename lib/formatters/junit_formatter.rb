# frozen_string_literal: true

require 'rexml/document'
require_relative 'base_formatter'

module Formatters
  # Formats output as JUnit XML
  # Compatible with CI/CD systems that consume JUnit test reports
  class JunitFormatter < BaseFormatter
    # Format data as JUnit XML
    #
    # @param data [Hash] Data to format
    # @param command [Symbol] The command type
    # @return [String] JUnit XML string
    def format(data, command:)
      case command
      when :lint
        format_lint_junit(data)
      when :dry_run
        format_dry_run_junit(data)
      else
        # DAG doesn't make sense as JUnit, fall back to empty report
        generate_empty_junit
      end
    end

    private

    # Format lint results as JUnit XML
    #
    # @param data [Hash] Lint results
    # @return [String] JUnit XML
    def format_lint_junit(data)
      doc = REXML::Document.new
      doc << REXML::XMLDecl.new('1.0', 'UTF-8')

      testsuites = doc.add_element('testsuites')
      testsuite = testsuites.add_element('testsuite', {
        'name' => 'GitLab CI Lint',
        'tests' => '1',
        'failures' => data[:valid] ? '0' : '1',
        'time' => '0'
      })

      testcase = testsuite.add_element('testcase', {
        'name' => 'yaml_validation',
        'time' => '0'
      })

      unless data[:valid]
        failure = testcase.add_element('failure', {
          'message' => 'GitLab CI configuration is invalid'
        })
        failure.text = (data[:errors] || []).join("\n")
      end

      formatter = REXML::Formatters::Pretty.new
      output = String.new
      formatter.write(doc, output)
      output
    end

    # Format dry-run results as JUnit XML
    #
    # @param data [Hash] Dry-run results
    # @return [String] JUnit XML
    def format_dry_run_junit(data)
      doc = REXML::Document.new
      doc << REXML::XMLDecl.new('1.0', 'UTF-8')

      jobs = Array(data[:jobs])
      failed_count = jobs.count { |job| job[:status] == 'failed' || job['status'] == 'failed' }

      testsuites = doc.add_element('testsuites')
      testsuite = testsuites.add_element('testsuite', {
        'name' => 'gitlab_ci_cli_dry_run',
        'tests' => jobs.size.to_s,
        'failures' => failed_count.to_s,
        'time' => calculate_total_time(data).to_s
      })

      # Add properties with metadata
      properties = testsuite.add_element('properties')
      properties.add_element('property', {
        'name' => 'command',
        'value' => 'dry_run'
      })
      properties.add_element('property', {
        'name' => 'pipeline_id',
        'value' => data[:pipeline_id].to_s
      })

      # Create testcase for each job
      jobs.each do |job|
        job_name = job[:name] || job['name']
        job_status = job[:status] || job['status']
        job_time = job[:duration] || job['duration'] || 0

        testcase = testsuite.add_element('testcase', {
          'name' => job_name.to_s,
          'classname' => 'pipeline_job',
          'time' => job_time.to_s
        })

        # Add failure element if job failed
        if job_status == 'failed'
          failure_message = job[:error] || job['error'] || 'Job execution failed'
          failure = testcase.add_element('failure', {
            'message' => failure_message
          })

          # Add failure details if available
          if job[:output] || job['output']
            failure.text = job[:output] || job['output']
          end
        end
      end

      # Add system-out with event timeline if available
      if data[:events] && !data[:events].empty?
        system_out = testsuite.add_element('system-out')
        system_out.text = format_events_for_output(data[:events])
      end

      formatter = REXML::Formatters::Pretty.new
      output = String.new
      formatter.write(doc, output)
      output
    end

    # Calculate total time from events or jobs
    #
    # @param data [Hash] Dry-run data
    # @return [Numeric] Total time in seconds
    def calculate_total_time(data)
      if data[:events] && !data[:events].empty?
        events = Array(data[:events])
        timestamps = events.map { |e| e[:timestamp] || e['timestamp'] || 0 }
        timestamps.max || 0
      elsif data[:jobs]
        jobs = Array(data[:jobs])
        jobs.sum { |j| j[:duration] || j['duration'] || 0 }
      else
        0
      end
    end

    # Format events as text for system-out
    #
    # @param events [Array] Event array
    # @return [String] Formatted events
    def format_events_for_output(events)
      Array(events).map do |event|
        timestamp = event[:timestamp] || event['timestamp'] || 0
        event_type = event[:type] || event['type']
        job_name = event[:job_name] || event['job_name']
        "[#{timestamp}s] #{event_type}: #{job_name}"
      end.join("\n")
    end

    # Generate empty JUnit report
    #
    # @return [String] JUnit XML
    def generate_empty_junit
      doc = REXML::Document.new
      doc << REXML::XMLDecl.new('1.0', 'UTF-8')
      testsuites = doc.add_element('testsuites')
      testsuite = testsuites.add_element('testsuite', {
        'name' => 'gitlab_ci_cli',
        'tests' => '0',
        'failures' => '0',
        'time' => '0'
      })

      formatter = REXML::Formatters::Pretty.new
      output = String.new
      formatter.write(doc, output)
      output
    end
  end
end
