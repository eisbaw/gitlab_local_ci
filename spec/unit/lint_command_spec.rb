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
require_relative '../spec_helper'
require 'tmpdir'
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

        result = Commands::LintCommand.execute(options.merge(PinnedPipelineContext.options))

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

        result = Commands::LintCommand.execute(options.merge(PinnedPipelineContext.options))

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

        result = Commands::LintCommand.execute(options.merge(PinnedPipelineContext.options))

        expect(result.valid).to be false
        expect(result.exit_code).to eq 1
        expect(result.errors).not_to be_empty
        expect(result.errors.first).to include('File not found')
      end
    end

    context 'with invalid GitLab directory' do
      it 'succeeds because gitlab_dir is ignored in standalone mode' do
        options = {
          entry: File.join(fixtures_dir, 'valid_simple.yml'),
          gitlab_dir: '/nonexistent/gitlab'
        }

        result = Commands::LintCommand.execute(options.merge(PinnedPipelineContext.options))

        # Standalone mode ignores gitlab_dir, so validation succeeds
        expect(result.valid).to be true
        expect(result.exit_code).to eq 0
        expect(result.errors).to be_empty
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

  describe 'parallel jobs (TASK-18)' do
    it 'accepts a need on one instance by its expanded name (gitlab-runner build.gitlab-ci.yml)' do
      Dir.mktmpdir('lint_parallel') do |dir|
        entry = File.join(dir, '.gitlab-ci.yml')
        File.write(entry, <<~YAML)
          helper images:
            stage: build
            script: [echo]
            parallel:
              matrix:
                - TARGETS: [alpine alpine-pwsh, windows]
          prebuilt helper images:
            stage: build
            script: [echo]
            needs: ["helper images: [alpine alpine-pwsh]"]
        YAML
        result = described_class.execute({ entry: entry, gitlab_dir: dir }.merge(PinnedPipelineContext.options))
        expect(result.errors).to eq([])
        expect(result.jobs).to eq(['helper images: [alpine alpine-pwsh]', 'helper images: [windows]', 'prebuilt helper images'])
      end
    end

    it "reports invalid parallel: in upstream's wording" do
      Dir.mktmpdir('lint_parallel') do |dir|
        entry = File.join(dir, '.gitlab-ci.yml')
        File.write(entry, "j:\n  script: [echo]\n  parallel: 201\n")
        result = described_class.execute({ entry: entry, gitlab_dir: dir }.merge(PinnedPipelineContext.options))
        expect(result.errors).to eq(['jobs:j:parallel config must be less than or equal to 200'])
      end
    end
  end

  # Upstream Entry::Jobs types a '.'-key as Entry::Hidden: not visible, not
  # relevant, never an Entry::Job. CI Lint neither lists, counts, warns
  # about nor validates it as a job (TASK-73).
  describe 'hidden templates' do
    def lint(yaml)
      Dir.mktmpdir('lint_hidden') do |dir|
        entry = File.join(dir, '.gitlab-ci.yml')
        File.write(entry, yaml)
        described_class.execute({ entry: entry, gitlab_dir: dir }.merge(PinnedPipelineContext.options))
      end
    end

    it 'leaves them out of the job list and warnings' do
      result = lint(<<~YAML)
        .unit:
          script: [echo unit]
        test:
          extends: .unit
          parallel:
            matrix:
              - OS: [linux, macos]
        build:
          script: [echo build]
      YAML
      expect(result.errors).to eq([])
      expect(result.jobs).to eq(['test: [linux]', 'test: [macos]', 'build'])
      expect(result.warnings).to eq([])
    end

    it 'does not validate them as jobs' do
      result = lint(<<~YAML)
        .unused_tpl:
          script: []
          needs: [nowhere]
          bogus_key: 1
        job:
          script: [echo]
      YAML
      expect(result.errors).to eq([])
      expect(result.jobs).to eq(['job'])
      expect(result.warnings).to eq([])
    end

    it 'is not a config with jobs when only hidden keys exist' do
      result = lint(".tpl:\n  script: [echo]\n")
      expect(result.valid).to be false
      expect(result.jobs).to eq([])
    end

    it 'cannot be needed: a hidden key is no job' do
      result = lint(<<~YAML)
        .tpl:
          script: [echo]
        job:
          script: [echo]
          needs: [.tpl]
      YAML
      expect(result.errors).to eq(["Job 'job' needs undefined job '.tpl'"])
    end
  end
end
