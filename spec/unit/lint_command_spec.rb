# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/commands/lint_command'

RSpec.describe Commands::LintCommand do
  let(:gitlab_dir) { File.expand_path('../../gitlab', __dir__) }
  let(:fixtures_dir) { File.expand_path('../fixtures/yaml', __dir__) }

  describe '.execute' do
    context 'with valid simple YAML' do
      it 'returns success result with stages and jobs' do
        options = {
          entry: File.join(fixtures_dir, 'valid_simple.yml'),
          gitlab_dir: gitlab_dir
        }

        result = Commands::LintCommand.execute(options)

        expect(result.valid).to be true
        expect(result.exit_code).to eq 0
        expect(result.stages).not_to be_empty
        expect(result.jobs).not_to be_empty
        expect(result.errors).to be_empty
      end
    end

    context 'with invalid YAML syntax' do
      it 'returns failure result with syntax error' do
        options = {
          entry: File.join(fixtures_dir, 'invalid_syntax.yml'),
          gitlab_dir: gitlab_dir
        }

        result = Commands::LintCommand.execute(options)

        expect(result.valid).to be false
        expect(result.exit_code).to eq 1
        expect(result.errors).not_to be_empty
        expect(result.errors.first).to include('syntax error')
      end
    end

    context 'with non-existent file' do
      it 'returns failure result with file not found error' do
        options = {
          entry: '/nonexistent/file.yml',
          gitlab_dir: gitlab_dir
        }

        result = Commands::LintCommand.execute(options)

        expect(result.valid).to be false
        expect(result.exit_code).to eq 1
        expect(result.errors).not_to be_empty
        expect(result.errors.first).to include('File not found')
      end
    end

    context 'with invalid GitLab directory' do
      it 'returns failure result with GitLab submodule error' do
        options = {
          entry: File.join(fixtures_dir, 'valid_simple.yml'),
          gitlab_dir: '/nonexistent/gitlab'
        }

        result = Commands::LintCommand.execute(options)

        expect(result.valid).to be false
        expect(result.exit_code).to eq 1
        expect(result.errors).not_to be_empty
        expect(result.errors.first).to match(/GitLab submodule|Failed to load/)
      end
    end
  end

  describe 'Result#to_h' do
    it 'converts result to hash for formatter consumption' do
      result = Commands::LintCommand::Result.new(
        valid: true,
        stages: %w[build test],
        jobs: %w[job1 job2],
        errors: [],
        exit_code: 0
      )

      hash = result.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:valid]).to be true
      expect(hash[:stages]).to eq(%w[build test])
      expect(hash[:jobs]).to eq(%w[job1 job2])
      expect(hash[:errors]).to eq([])
    end
  end
end
