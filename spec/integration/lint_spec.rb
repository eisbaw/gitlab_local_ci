# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'GitLab CI Lint Command', type: :integration do
  let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }
  let(:fixtures_path) { File.expand_path('../fixtures/yaml', __dir__) }
  let(:valid_simple_file) { File.join(fixtures_path, 'valid_simple.yml') }
  let(:invalid_syntax_file) { File.join(fixtures_path, 'invalid_syntax.yml') }
  let(:circular_dependency_file) { File.join(fixtures_path, 'circular_dependency.yml') }
  let(:valid_with_needs_file) { File.join(fixtures_path, 'valid_with_needs.yml') }

  # Helper method to execute CLI command
  # Returns: [stdout, stderr, exit_status]
  def run_lint(file_path, format: 'text', extra_args: [])
    args = ['lint', '--entry', file_path, '--format', format] + extra_args
    stdout, stderr, status = Open3.capture3(bin_path, *args)
    [stdout, stderr, status.exitstatus]
  end

  context 'with valid YAML files' do
    describe 'valid_simple.yml' do
      it 'passes validation and exits with status 0' do
        stdout, stderr, status = run_lint(valid_simple_file)

        expect(status).to eq(0), "Expected exit status 0, got #{status}. STDERR: #{stderr}"
        expect(stderr).to be_empty, "Expected no errors but got: #{stderr}"
      end

      it 'displays pipeline structure information' do
        stdout, _stderr, _status = run_lint(valid_simple_file)

        # Verify it shows stages
        expect(stdout).to match(/stages?/i)
        expect(stdout).to include('build')
        expect(stdout).to include('test')
        expect(stdout).to include('deploy')

        # Verify it shows job count
        expect(stdout).to match(/jobs?.*3/i)
      end

      it 'produces valid JSON output format' do
        stdout, _stderr, status = run_lint(valid_simple_file, format: 'json')

        expect(status).to eq(0)

        # Parse JSON to verify format
        expect { JSON.parse(stdout) }.not_to raise_error
        result = JSON.parse(stdout)

        expect(result).to have_key('valid')
        expect(result['valid']).to be true
        expect(result).to have_key('stages')
        expect(result['stages']).to include('build', 'test', 'deploy')
      end

      it 'produces valid JUnit XML output format' do
        stdout, _stderr, status = run_lint(valid_simple_file, format: 'junit')

        expect(status).to eq(0)

        # Verify JUnit XML structure (REXML uses single quotes)
        expect(stdout).to include('<?xml version=')
        expect(stdout).to include('<testsuites')
        expect(stdout).to include('<testsuite')
        expect(stdout).to include('GitLab CI Lint')
        expect(stdout).to include('<testcase')

        # Should not contain failure elements for valid config
        expect(stdout).not_to include('<failure')
      end
    end

    describe 'valid_with_needs.yml' do
      it 'passes validation with complex DAG dependencies' do
        stdout, stderr, status = run_lint(valid_with_needs_file)

        expect(status).to eq(0)
        expect(stderr).to be_empty

        # Verify stages are detected
        expect(stdout).to include('prepare')
        expect(stdout).to include('build')
        expect(stdout).to include('test')
        expect(stdout).to include('deploy')
      end

      it 'validates needs dependencies are acyclic' do
        stdout, _stderr, status = run_lint(valid_with_needs_file)

        expect(status).to eq(0)

        # Should not report circular dependency errors
        expect(stdout.downcase).not_to match(/circular.*dependency/i)
        expect(stdout.downcase).not_to match(/cycle/i)
      end
    end
  end

  context 'with invalid YAML files' do
    describe 'invalid_syntax.yml' do
      it 'fails validation and exits with non-zero status' do
        stdout, stderr, status = run_lint(invalid_syntax_file)

        expect(status).not_to eq(0), "Expected non-zero exit status for invalid YAML"
      end

      it 'reports syntax errors clearly' do
        stdout, stderr, status = run_lint(invalid_syntax_file)

        # Combined output should contain error indicators
        combined_output = stdout + stderr

        expect(combined_output).to match(/error|invalid|fail/i),
          "Expected error message in output: #{combined_output}"
      end

      it 'produces JSON error output with validation errors' do
        stdout, _stderr, status = run_lint(invalid_syntax_file, format: 'json')

        expect(status).not_to eq(0)

        # Should produce valid JSON even on error
        expect { JSON.parse(stdout) }.not_to raise_error
        result = JSON.parse(stdout)

        expect(result['valid']).to be false
        expect(result).to have_key('errors')
        expect(result['errors']).to be_an(Array)
        expect(result['errors']).not_to be_empty
      end

      it 'produces JUnit XML with failure elements' do
        stdout, _stderr, status = run_lint(invalid_syntax_file, format: 'junit')

        expect(status).not_to eq(0)

        # Verify JUnit XML contains failure (REXML uses single quotes)
        expect(stdout).to include('<?xml version=')
        expect(stdout).to include('<testsuites')
        expect(stdout).to include('<failure')
      end
    end

    describe 'circular_dependency.yml' do
      it 'detects circular dependencies and exits with error' do
        stdout, stderr, status = run_lint(circular_dependency_file)

        expect(status).not_to eq(0), "Expected non-zero exit for circular dependency"
      end

      it 'reports circular dependency with job names' do
        stdout, stderr, status = run_lint(circular_dependency_file)

        combined_output = (stdout + stderr).downcase

        # Should mention circular dependency
        expect(combined_output).to match(/circular.*dependency|cycle/i)

        # Should mention the jobs involved
        expect(combined_output).to match(/job-a|job-b/)
      end

      it 'reports circular dependency in JSON format' do
        stdout, _stderr, status = run_lint(circular_dependency_file, format: 'json')

        expect(status).not_to eq(0)

        result = JSON.parse(stdout)
        expect(result['valid']).to be false

        # Errors should mention circular dependency
        error_text = result['errors'].join(' ').downcase
        expect(error_text).to match(/circular|cycle/)
      end
    end

    describe 'missing file' do
      it 'reports file not found error' do
        stdout, stderr, status = run_lint('/nonexistent/file.yml')

        expect(status).not_to eq(0)

        combined_output = stdout + stderr
        expect(combined_output).to match(/not found|no such file|does not exist/i)
      end

      it 'exits with error status for missing file' do
        _stdout, _stderr, status = run_lint('/nonexistent/file.yml')

        expect(status).not_to eq(0)
      end
    end
  end

  context 'output format options' do
    describe '--format text' do
      it 'produces human-readable output' do
        stdout, _stderr, _status = run_lint(valid_simple_file, format: 'text')

        # Should be readable (not JSON/XML)
        expect(stdout).not_to match(/^{/)
        expect(stdout).not_to match(/^<\?xml/)

        # Should contain meaningful words
        expect(stdout).to match(/\w+/)
      end
    end

    describe '--format json' do
      it 'produces parseable JSON for valid config' do
        stdout, _stderr, _status = run_lint(valid_simple_file, format: 'json')

        expect { JSON.parse(stdout) }.not_to raise_error
        result = JSON.parse(stdout)

        expect(result).to be_a(Hash)
        expect(result).to have_key('valid')
      end

      it 'produces parseable JSON for invalid config' do
        stdout, _stderr, _status = run_lint(invalid_syntax_file, format: 'json')

        expect { JSON.parse(stdout) }.not_to raise_error
        result = JSON.parse(stdout)

        expect(result).to be_a(Hash)
        expect(result['valid']).to be false
      end
    end

    describe '--format junit' do
      it 'produces valid XML structure' do
        stdout, _stderr, _status = run_lint(valid_simple_file, format: 'junit')

        # Basic XML validation (REXML uses single quotes)
        expect(stdout).to include('<?xml version=')
        expect(stdout).to match(/<testsuites.*>/)
        expect(stdout).to include('</testsuites>')

        # Proper nesting - opening tags should match closing tags
        expect(stdout.scan(/<testsuite\s/).size).to be >= 1
        expect(stdout.scan(/<testsuite\s/).size).to eq(stdout.scan(/<\/testsuite>/).size)
      end

      it 'includes test case elements' do
        stdout, _stderr, _status = run_lint(valid_simple_file, format: 'junit')

        expect(stdout).to include('<testcase')
        expect(stdout).to include('name=')
      end
    end

    describe 'invalid format' do
      it 'reports error for unsupported format' do
        stdout, stderr, status = run_lint(valid_simple_file, format: 'invalid_format')

        expect(status).not_to eq(0)

        combined_output = stdout + stderr
        expect(combined_output).to match(/unsupported|invalid|unknown.*format/i)
      end
    end
  end

  context 'verbose mode' do
    it 'provides additional diagnostic information' do
      stdout_normal, _stderr, _status = run_lint(valid_simple_file)
      stdout_verbose, _stderr, _status = run_lint(valid_simple_file, extra_args: ['--verbose'])

      # Verbose should produce more output
      expect(stdout_verbose.length).to be >= stdout_normal.length
    end
  end

  context 'error handling' do
    it 'handles missing --entry flag gracefully' do
      stdout, stderr, status = Open3.capture3(bin_path, 'lint')

      expect(status).not_to eq(0)

      combined_output = stdout + stderr
      # Should report error about missing file or entry
      expect(combined_output).to match(/entry|file.*required|file not found|\.gitlab-ci\.yml/i)
    end

    it 'provides helpful error for invalid flags' do
      stdout, stderr, status = Open3.capture3(bin_path, 'lint', '--invalid-flag')

      expect(status).not_to eq(0)

      combined_output = stdout + stderr
      expect(combined_output).to match(/unknown|invalid.*option|flag/i)
    end
  end
end
