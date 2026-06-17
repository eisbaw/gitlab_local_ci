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
require 'spec_helper'
require 'gitlab_ci_cli'

RSpec.describe GitlabCiCli::CLI do
  describe '.parse_args' do
    context 'with no arguments' do
      it 'defaults to help command' do
        options, command = described_class.parse_args([])
        expect(command).to eq('help')
      end

      it 'uses default options' do
        options, = described_class.parse_args([])
        expect(options[:entry]).to eq('./.gitlab-ci.yml')
        expect(options[:project]).to eq(Dir.pwd)
        expect(options[:runners]).to eq('./runners')
        expect(options[:ref]).to eq('HEAD')
        expect(options[:pipeline]).to eq('push')
        expect(options[:undefined]).to eq('warning')
        expect(options[:format]).to eq('text')
        expect(options[:gitlab_dir]).to eq('./gitlab')
        expect(options[:verbose]).to eq(false)
        expect(options[:variables]).to eq({})
      end
    end

    context 'with valid commands' do
      it 'parses lint command' do
        _, command = described_class.parse_args(['lint'])
        expect(command).to eq('lint')
      end

      it 'parses dag command' do
        _, command = described_class.parse_args(['dag'])
        expect(command).to eq('dag')
      end

      it 'parses dry-run command' do
        _, command = described_class.parse_args(['dry-run'])
        expect(command).to eq('dry-run')
      end

      it 'parses help command' do
        _, command = described_class.parse_args(['help'])
        expect(command).to eq('help')
      end
    end

    context 'with invalid commands' do
      it 'raises ArgumentError for unknown command' do
        expect do
          described_class.parse_args(['invalid'])
        end.to raise_error(ArgumentError, /Unknown command: invalid/)
      end

      it 'raises ArgumentError for multiple commands' do
        expect do
          described_class.parse_args(['lint', 'dag'])
        end.to raise_error(ArgumentError, /Multiple commands or unexpected argument: dag/)
      end
    end

    context 'with --help flag' do
      it 'returns help command immediately' do
        _, command = described_class.parse_args(['--help'])
        expect(command).to eq('help')
      end

      it 'works with -h shorthand' do
        _, command = described_class.parse_args(['-h'])
        expect(command).to eq('help')
      end
    end

    context 'with --version flag' do
      it 'prints version and exits' do
        expect do
          described_class.parse_args(['--version'])
        end.to output("gitlab_ci_cli version #{GitlabCiCli::VERSION}\n").to_stdout
          .and raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end

      it 'works with -v shorthand' do
        expect do
          described_class.parse_args(['-v'])
        end.to output("gitlab_ci_cli version #{GitlabCiCli::VERSION}\n").to_stdout
          .and raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      end
    end

    context 'with --entry flag' do
      it 'parses custom entry file' do
        options, = described_class.parse_args(['--entry', 'custom.yml', 'lint'])
        expect(options[:entry]).to eq('custom.yml')
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--entry'])
        end.to raise_error(ArgumentError, /Flag --entry requires a value/)
      end

      it 'raises error when value starts with --' do
        expect do
          described_class.parse_args(['--entry', '--verbose'])
        end.to raise_error(ArgumentError, /Flag --entry requires a value/)
      end
    end

    context 'with --project flag' do
      it 'parses custom project directory' do
        options, = described_class.parse_args(['--project', '/path/to/project', 'lint'])
        expect(options[:project]).to eq('/path/to/project')
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--project'])
        end.to raise_error(ArgumentError, /Flag --project requires a value/)
      end
    end

    context 'with --runners flag' do
      it 'parses custom runners directory' do
        options, = described_class.parse_args(['--runners', '/path/to/runners', 'dry-run'])
        expect(options[:runners]).to eq('/path/to/runners')
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--runners'])
        end.to raise_error(ArgumentError, /Flag --runners requires a value/)
      end
    end

    context 'with --ref flag' do
      it 'parses custom git ref' do
        options, = described_class.parse_args(['--ref', 'main', 'lint'])
        expect(options[:ref]).to eq('main')
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--ref'])
        end.to raise_error(ArgumentError, /Flag --ref requires a value/)
      end
    end

    context 'with --pipeline flag' do
      it 'parses push pipeline type' do
        options, = described_class.parse_args(['--pipeline', 'push', 'dry-run'])
        expect(options[:pipeline]).to eq('push')
      end

      it 'parses merge_request pipeline type' do
        options, = described_class.parse_args(['--pipeline', 'merge_request', 'dry-run'])
        expect(options[:pipeline]).to eq('merge_request')
      end

      it 'parses schedule pipeline type' do
        options, = described_class.parse_args(['--pipeline', 'schedule', 'dry-run'])
        expect(options[:pipeline]).to eq('schedule')
      end

      it 'parses manual pipeline type' do
        options, = described_class.parse_args(['--pipeline', 'manual', 'dry-run'])
        expect(options[:pipeline]).to eq('manual')
      end

      it 'raises error for invalid pipeline type' do
        expect do
          described_class.parse_args(['--pipeline', 'invalid', 'dry-run'])
        end.to raise_error(ArgumentError, /Invalid value 'invalid' for --pipeline/)
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--pipeline'])
        end.to raise_error(ArgumentError, /Flag --pipeline requires a value/)
      end
    end

    context 'with --variables flag' do
      it 'parses single variable' do
        options, = described_class.parse_args(['--variables', 'FOO=bar', 'dry-run'])
        expect(options[:variables]).to eq({ 'FOO' => 'bar' })
      end

      it 'parses multiple variables' do
        options, = described_class.parse_args([
          '--variables', 'FOO=bar',
          '--variables', 'BAZ=qux',
          'dry-run'
        ])
        expect(options[:variables]).to eq({ 'FOO' => 'bar', 'BAZ' => 'qux' })
      end

      it 'parses variable with equals in value' do
        options, = described_class.parse_args(['--variables', 'KEY=val=with=equals', 'dry-run'])
        expect(options[:variables]).to eq({ 'KEY' => 'val=with=equals' })
      end

      it 'raises error for invalid format' do
        expect do
          described_class.parse_args(['--variables', 'INVALID', 'dry-run'])
        end.to raise_error(ArgumentError, /requires KEY=VALUE format, got: INVALID/)
      end

      it 'raises error for empty key' do
        expect do
          described_class.parse_args(['--variables', '=value', 'dry-run'])
        end.to raise_error(ArgumentError, /requires KEY=VALUE format/)
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--variables'])
        end.to raise_error(ArgumentError, /Flag --variables requires a value/)
      end
    end

    context 'with --env flag (alias for --variables)' do
      it 'parses single environment variable' do
        options, = described_class.parse_args(['--env', 'FOO=bar', 'dry-run'])
        expect(options[:variables]).to eq({ 'FOO' => 'bar' })
      end

      it 'combines with --variables flag' do
        options, = described_class.parse_args([
          '--variables', 'FOO=bar',
          '--env', 'BAZ=qux',
          'dry-run'
        ])
        expect(options[:variables]).to eq({ 'FOO' => 'bar', 'BAZ' => 'qux' })
      end
    end

    context 'with --undefined flag' do
      it 'parses warning mode' do
        options, = described_class.parse_args(['--undefined', 'warning', 'dry-run'])
        expect(options[:undefined]).to eq('warning')
      end

      it 'parses error mode' do
        options, = described_class.parse_args(['--undefined', 'error', 'dry-run'])
        expect(options[:undefined]).to eq('error')
      end

      it 'parses empty mode' do
        options, = described_class.parse_args(['--undefined', 'empty', 'dry-run'])
        expect(options[:undefined]).to eq('empty')
      end

      it 'raises error for invalid mode' do
        expect do
          described_class.parse_args(['--undefined', 'invalid', 'dry-run'])
        end.to raise_error(ArgumentError, /Invalid value 'invalid' for --undefined/)
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--undefined'])
        end.to raise_error(ArgumentError, /Flag --undefined requires a value/)
      end
    end

    context 'with --verbose flag' do
      it 'enables verbose mode' do
        options, = described_class.parse_args(['--verbose', 'lint'])
        expect(options[:verbose]).to eq(true)
      end

      it 'defaults to false' do
        options, = described_class.parse_args(['lint'])
        expect(options[:verbose]).to eq(false)
      end
    end

    context 'with --format flag' do
      it 'parses text format' do
        options, = described_class.parse_args(['--format', 'text', 'lint'])
        expect(options[:format]).to eq('text')
      end

      it 'parses json format' do
        options, = described_class.parse_args(['--format', 'json', 'lint'])
        expect(options[:format]).to eq('json')
      end

      it 'parses junit format' do
        options, = described_class.parse_args(['--format', 'junit', 'lint'])
        expect(options[:format]).to eq('junit')
      end

      it 'raises error for invalid format' do
        expect do
          described_class.parse_args(['--format', 'invalid', 'lint'])
        end.to raise_error(ArgumentError, /Invalid value 'invalid' for --format/)
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--format'])
        end.to raise_error(ArgumentError, /Flag --format requires a value/)
      end
    end

    context 'with --gitlab-dir flag' do
      it 'parses custom gitlab directory' do
        options, = described_class.parse_args(['--gitlab-dir', '/path/to/gitlab', 'lint'])
        expect(options[:gitlab_dir]).to eq('/path/to/gitlab')
      end

      it 'raises error when value is missing' do
        expect do
          described_class.parse_args(['--gitlab-dir'])
        end.to raise_error(ArgumentError, /Flag --gitlab-dir requires a value/)
      end
    end

    context 'with unknown flags' do
      it 'raises ArgumentError' do
        expect do
          described_class.parse_args(['--unknown-flag', 'lint'])
        end.to raise_error(ArgumentError, /Unknown flag: --unknown-flag/)
      end
    end

    context 'with complex flag combinations' do
      it 'parses multiple flags with command' do
        options, command = described_class.parse_args([
          '--entry', 'custom.yml',
          '--project', '/path/to/project',
          '--ref', 'main',
          '--verbose',
          '--format', 'json',
          'lint'
        ])

        expect(command).to eq('lint')
        expect(options[:entry]).to eq('custom.yml')
        expect(options[:project]).to eq('/path/to/project')
        expect(options[:ref]).to eq('main')
        expect(options[:verbose]).to eq(true)
        expect(options[:format]).to eq('json')
      end

      it 'parses flags before and after command' do
        options, command = described_class.parse_args([
          '--verbose',
          'dry-run',
          '--variables', 'FOO=bar',
          '--runners', './custom-runners'
        ])

        expect(command).to eq('dry-run')
        expect(options[:verbose]).to eq(true)
        expect(options[:variables]).to eq({ 'FOO' => 'bar' })
        expect(options[:runners]).to eq('./custom-runners')
      end
    end
  end

  describe '.execute_command' do
    context 'with help command' do
      it 'prints help and returns success' do
        expect do
          exit_code = described_class.execute_command('help', {})
          expect(exit_code).to eq(described_class::EXIT_SUCCESS)
        end.to output(/gitlab_ci_cli - Local GitLab CI Pipeline Simulator/).to_stdout
      end
    end

    context 'with invalid command' do
      it 'prints error and returns failure' do
        expect do
          exit_code = described_class.execute_command('invalid', {})
          expect(exit_code).to eq(described_class::EXIT_COMMAND_FAILED)
        end.to output(/BUG: Unhandled command/).to_stderr
      end
    end
  end

  describe '.print_help' do
    it 'prints comprehensive help message' do
      output = capture_stdout { described_class.print_help }

      expect(output).to include('gitlab_ci_cli - Local GitLab CI Pipeline Simulator')
      expect(output).to include('USAGE:')
      expect(output).to include('COMMANDS:')
      expect(output).to include('OPTIONS:')
      expect(output).to include('EXAMPLES:')
      expect(output).to include('lint')
      expect(output).to include('dag')
      expect(output).to include('dry-run')
    end
  end

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  describe '.print_version' do
    it 'prints version information' do
      expect do
        described_class.print_version
      end.to output("gitlab_ci_cli version #{GitlabCiCli::VERSION}\n").to_stdout
    end
  end

  describe 'MPED principles compliance' do
    it 'has no global state' do
      # Parse args multiple times with different inputs
      options1, = described_class.parse_args(['lint'])
      options2, = described_class.parse_args(['dag'])

      # Each call should produce independent results
      expect(options1[:entry]).to eq('./.gitlab-ci.yml')
      expect(options2[:entry]).to eq('./.gitlab-ci.yml')
    end

    it 'fails fast with clear error messages' do
      expect do
        described_class.parse_args(['--unknown'])
      end.to raise_error(ArgumentError, /Unknown flag: --unknown/)
    end

    it 'validates input before processing' do
      # Invalid enum values should fail immediately
      expect do
        described_class.parse_args(['--pipeline', 'invalid', 'dry-run'])
      end.to raise_error(ArgumentError, /Invalid value/)
    end

    it 'uses immutable default values' do
      # DEFAULTS constant should be frozen
      expect(described_class::DEFAULTS).to be_frozen

      # Parsing should not mutate defaults
      original_defaults = described_class::DEFAULTS.dup
      described_class.parse_args(['lint'])
      expect(described_class::DEFAULTS).to eq(original_defaults)
    end

    it 'has composable functions' do
      # Each helper function should work independently
      expect(described_class.require_value('--test', 'value')).to eq('value')

      expect do
        described_class.validate_enum('--test', 'valid', %w[valid invalid])
      end.not_to raise_error

      key, val = described_class.parse_key_value('--test', 'KEY=VALUE')
      expect(key).to eq('KEY')
      expect(val).to eq('VALUE')
    end
  end
end
