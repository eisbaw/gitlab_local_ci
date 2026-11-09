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

  # Upstream External::Processor#perform: merge_external_files! (in include
  # order, nested includes expanded first) then append_inline_content!, all
  # via ActiveSupport deep_merge!: hashes merge, anything else is replaced.
  # So: main file > later include > earlier include > nested include.
  describe 'merge precedence' do
    def process_in_tmpdir(files, config)
      Dir.mktmpdir do |tmpdir|
        files.each { |name, body| File.write(File.join(tmpdir, name), body) }
        described_class.new(project_path: tmpdir).process_includes(config)
      end
    end

    it 'lets the main file win over an included file (TASK-5 repro)' do
      result = process_in_tmpdir(
        { 'inc.yml' => "job1:\n  script: echo included\n  tags: [x]\n" },
        { 'include' => [{ 'local' => 'inc.yml' }], 'job1' => { 'script' => 'echo main' } }
      )

      expect(result['job1']).to eq('script' => 'echo main', 'tags' => ['x'])
      expect(result).not_to have_key('include')
    end

    it 'lets a later include win over an earlier include' do
      result = process_in_tmpdir(
        {
          'a.yml' => "variables: {V: a, ONLY_A: a}\njob: {script: [echo a], tags: [a]}\n",
          'b.yml' => "variables: {V: b}\njob: {script: [echo b]}\n"
        },
        { 'include' => ['a.yml', 'b.yml'] }
      )

      expect(result['variables']).to eq('V' => 'b', 'ONLY_A' => 'a')
      expect(result['job']).to eq('script' => ['echo b'], 'tags' => ['a'])
    end

    it 'lets an including file win over its own nested include' do
      result = process_in_tmpdir(
        {
          'outer.yml' => "include: inner.yml\njob: {script: [echo outer]}\n",
          'inner.yml' => "job: {script: [echo inner], stage: test, tags: [inner]}\n"
        },
        { 'include' => 'outer.yml', 'job' => { 'tags' => ['main'] } }
      )

      expect(result['job']).to eq('script' => ['echo outer'], 'stage' => 'test', 'tags' => ['main'])
    end

    it 'replaces arrays from includes instead of concatenating them' do
      result = process_in_tmpdir(
        { 'inc.yml' => "stages: [build, test, deploy]\njob: {before_script: [inc]}\n" },
        { 'include' => 'inc.yml', 'stages' => ['build'], 'job' => { 'before_script' => ['main'] } }
      )

      expect(result['stages']).to eq(['build'])
      expect(result['job']['before_script']).to eq(['main'])
    end

    it 'places included keys first, then main-only keys (upstream deep_merge! key order)' do
      result = process_in_tmpdir(
        { 'inc.yml' => "inc_job: {script: [x]}\nshared: {script: [x]}\n" },
        { 'main_job' => { 'script' => ['y'] }, 'include' => 'inc.yml', 'shared' => { 'script' => ['y'] } }
      )

      expect(result.keys).to eq(%w[inc_job shared main_job])
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

    context 'with include rules evaluated against variables' do
      it 'skips an include whose rule does not match when variable is unset' do
        config = {
          'include' => [
            { 'local' => 'topic_a.yml',
              'rules' => [{ 'if' => '$FEATURE_A =~ /.+/' }] }
          ]
        }

        result = processor.process_includes(config)

        expect(result.key?('topic_a_job')).to be false
      end

      it 'merges an include whose rule matches when variable is set via --variables' do
        proc_with_vars = described_class.new(
          project_path: fixtures_path,
          variables: { 'FEATURE_A' => 'enabled' }
        )

        config = {
          'include' => [
            { 'local' => 'topic_a.yml',
              'rules' => [{ 'if' => '$FEATURE_A =~ /.+/' }] }
          ]
        }

        result = proc_with_vars.process_includes(config)

        expect(result['topic_a_job']).to be_a(Hash)
      end

      it 'selects exactly one include among mutually-exclusive rules' do
        # Mirror a real-world topic-routing pattern: positive-only rules,
        # exactly one matches per variable set.
        mutually_exclusive = lambda do |vars|
          described_class.new(project_path: fixtures_path, variables: vars).process_includes(
            {
              'include' => [
                { 'local' => 'topic_a.yml',
                  'rules' => [{ 'if' => '$TOPIC == "a"' }] },
                { 'local' => 'topic_b.yml',
                  'rules' => [{ 'if' => '$TOPIC == "b"' }] }
              ]
            }
          )
        end

        result_a = mutually_exclusive.call({ 'TOPIC' => 'a' })
        expect(result_a.key?('topic_a_job')).to be true
        expect(result_a.key?('topic_b_job')).to be false

        result_b = mutually_exclusive.call({ 'TOPIC' => 'b' })
        expect(result_b.key?('topic_a_job')).to be false
        expect(result_b.key?('topic_b_job')).to be true
      end

      it 'honors when: never on include rules' do
        proc_with_vars = described_class.new(
          project_path: fixtures_path,
          variables: { 'FEATURE_A' => 'enabled' }
        )

        config = {
          'include' => [
            { 'local' => 'topic_a.yml',
              'rules' => [{ 'if' => '$FEATURE_A =~ /.+/', 'when' => 'never' }] }
          ]
        }

        result = proc_with_vars.process_includes(config)

        expect(result.key?('topic_a_job')).to be false
      end

      it 'merges include without any rules unconditionally' do
        config = {
          'include' => [
            { 'local' => 'topic_a.yml' }
          ]
        }

        result = processor.process_includes(config)

        expect(result['topic_a_job']).to be_a(Hash)
      end
    end
  end
end
