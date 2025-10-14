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
require 'include_processor'
require 'tmpdir'

RSpec.describe IncludeProcessor do
  let(:fixtures_path) { File.expand_path('../fixtures/includes', __dir__) }
  let(:processor) { described_class.new(project_path: fixtures_path) }

  describe '#initialize' do
    it 'initializes with project path' do
      expect(processor.project_path).to eq(fixtures_path)
    end

    it 'initializes processed_includes set' do
      expect(processor.instance_variable_get(:@processed_includes)).to be_a(Set)
    end
  end

  describe '#process_includes' do
    context 'with no includes' do
      it 'returns config unchanged' do
        config = { 'stages' => ['build'], 'build_job' => { 'script' => ['echo test'] } }
        result = processor.process_includes(config)

        expect(result).to eq(config)
      end
    end

    context 'with local include as string' do
      it 'processes local include' do
        config = {
          'include' => 'extra_jobs.yml',
          'stages' => ['build', 'test', 'deploy'],
          'build' => { 'stage' => 'build', 'script' => ['echo build'] }
        }

        result = processor.process_includes(config)

        expect(result['test_job']).to be_a(Hash)
        expect(result['test_job']['script']).to eq(['echo "Testing"'])
        expect(result['deploy_job']).to be_a(Hash)
        expect(result['include']).to be_nil # include key should be removed
      end
    end

    context 'with local include as hash' do
      it 'processes local include' do
        config = {
          'include' => { 'local' => 'extra_jobs.yml' },
          'stages' => ['build', 'test', 'deploy']
        }

        result = processor.process_includes(config)

        expect(result['test_job']).to be_a(Hash)
        expect(result['deploy_job']).to be_a(Hash)
      end
    end

    context 'with multiple includes' do
      it 'processes all includes in order' do
        config = {
          'include' => [
            'base.yml',
            'extra_jobs.yml'
          ]
        }

        result = processor.process_includes(config)

        expect(result['build_job']).to be_a(Hash)
        expect(result['test_job']).to be_a(Hash)
        expect(result['deploy_job']).to be_a(Hash)
      end
    end

    context 'with depth limit' do
      it 'raises error when depth exceeds MAX_DEPTH' do
        config = { 'stages' => ['build'] }

        expect {
          processor.process_includes(config, IncludeProcessor::MAX_DEPTH + 1)
        }.to raise_error(IncludeDepthExceededError)
      end
    end

    context 'with missing file' do
      it 'raises error for non-existent include' do
        config = { 'include' => 'nonexistent.yml' }

        expect {
          processor.process_includes(config)
        }.to raise_error(/Local include file not found/)
      end
    end
  end

  describe '#determine_include_type' do
    it 'detects string as local' do
      type = processor.send(:determine_include_type, 'file.yml')
      expect(type).to eq(:local)
    end

    it 'detects hash with local key' do
      type = processor.send(:determine_include_type, { 'local' => 'file.yml' })
      expect(type).to eq(:local)
    end

    it 'detects hash with remote key' do
      type = processor.send(:determine_include_type, { 'remote' => 'https://example.com/ci.yml' })
      expect(type).to eq(:remote)
    end

    it 'detects hash with template key' do
      type = processor.send(:determine_include_type, { 'template' => 'Auto-DevOps.gitlab-ci.yml' })
      expect(type).to eq(:template)
    end

    it 'detects hash with project key' do
      type = processor.send(:determine_include_type, { 'project' => 'group/project', 'file' => '.gitlab-ci.yml' })
      expect(type).to eq(:project)
    end

    it 'detects hash with component key' do
      type = processor.send(:determine_include_type, { 'component' => 'gitlab.com/components/test@1.0' })
      expect(type).to eq(:component)
    end
  end

  describe '#deep_merge' do
    it 'merges nested hashes' do
      base = {
        'variables' => { 'VAR1' => 'value1' },
        'job1' => { 'script' => ['echo 1'] }
      }
      overlay = {
        'variables' => { 'VAR2' => 'value2' },
        'job2' => { 'script' => ['echo 2'] }
      }

      result = processor.send(:deep_merge, base, overlay)

      expect(result['variables']['VAR1']).to eq('value1')
      expect(result['variables']['VAR2']).to eq('value2')
      expect(result['job1']).to eq({ 'script' => ['echo 1'] })
      expect(result['job2']).to eq({ 'script' => ['echo 2'] })
    end

    it 'replaces arrays instead of merging' do
      base = { 'stages' => ['build'] }
      overlay = { 'stages' => ['build', 'test'] }

      result = processor.send(:deep_merge, base, overlay)

      expect(result['stages']).to eq(['build', 'test'])
    end
  end

  describe '#include_identifier' do
    it 'generates identifier for string local include' do
      id = processor.send(:include_identifier, 'test.yml')
      expect(id).to start_with('local:')
      expect(id).to include('test.yml')
    end

    it 'generates identifier for hash local include' do
      id = processor.send(:include_identifier, { 'local' => 'test.yml' })
      expect(id).to start_with('local:')
    end

    it 'generates identifier for remote include' do
      id = processor.send(:include_identifier, { 'remote' => 'https://example.com/ci.yml' })
      expect(id).to eq('remote:https://example.com/ci.yml')
    end

    it 'generates identifier for template include' do
      id = processor.send(:include_identifier, { 'template' => 'Auto-DevOps.gitlab-ci.yml' })
      expect(id).to eq('template:Auto-DevOps.gitlab-ci.yml')
    end

    it 'generates identifier for project include' do
      id = processor.send(:include_identifier, { 'project' => 'group/project', 'file' => 'ci.yml', 'ref' => 'main' })
      expect(id).to eq('project:group/project:ci.yml:main')
    end
  end

  describe 'circular include detection' do
    it 'detects circular includes' do
      # Create a circular include scenario
      Dir.mktmpdir do |tmpdir|
        # File A includes B
        File.write(File.join(tmpdir, 'a.yml'), "include: b.yml\nstages: [build]")
        # File B includes A (circular)
        File.write(File.join(tmpdir, 'b.yml'), "include: a.yml\nstages: [test]")

        processor_tmp = described_class.new(project_path: tmpdir)
        config = { 'include' => 'a.yml' }

        expect {
          processor_tmp.process_includes(config)
        }.to raise_error(/Circular include detected/)
      end
    end
  end
end
