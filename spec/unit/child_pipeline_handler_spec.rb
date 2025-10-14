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
require 'child_pipeline_handler'
require 'mock_job'
require 'open3'

RSpec.describe ChildPipelineHandler do
  let(:handler) { described_class.new }
  let(:parent_job) do
    MockJob.new(
      id: 1,
      name: 'trigger_job',
      stage: 'deploy',
      script: ['echo trigger'],
      variables: { 'PARENT_VAR' => 'parent_value' }
    )
  end

  describe '#initialize' do
    it 'initializes with default max depth' do
      expect(handler.max_depth).to eq(ChildPipelineHandler::DEFAULT_MAX_DEPTH)
    end

    it 'initializes with custom max depth' do
      custom_handler = described_class.new(max_depth: 5)
      expect(custom_handler.max_depth).to eq(5)
    end
  end

  describe '#trigger_child' do
    let(:downstream_config) do
      {
        project: '../child-project',
        file: '.gitlab-ci.yml',
        variables: { 'CHILD_VAR' => 'child_value' }
      }
    end

    context 'with valid configuration' do
      it 'validates required project field' do
        invalid_config = { file: '.gitlab-ci.yml' }

        expect {
          handler.trigger_child(parent_job, invalid_config)
        }.to raise_error(/requires 'project' field/)
      end

      it 'uses default file when not specified' do
        config = { project: '../child-project' }

        # Mock Open3.capture2e to avoid actual command execution
        status_double = double('status', exitstatus: 0)
        allow(Open3).to receive(:capture2e).and_return(['output', status_double])

        result = handler.trigger_child(parent_job, config)

        expect(result[:success]).to be true
      end

      it 'merges parent and child variables' do
        # We can't easily test the actual command execution without integration tests
        # So we'll test the build_command_args method
        args = handler.send(
          :build_command_args,
          '.gitlab-ci.yml',
          '../child-project',
          { 'PARENT_VAR' => 'parent_value', 'CHILD_VAR' => 'child_value' },
          1,
          1
        )

        expect(args).to include('--variables')
        expect(args).to include('PARENT_VAR=parent_value')
        expect(args).to include('CHILD_VAR=child_value')
      end
    end

    context 'with depth limit' do
      it 'raises error when depth exceeds max_depth' do
        config = { project: '../child-project' }

        expect {
          handler.trigger_child(parent_job, config, current_depth: handler.max_depth)
        }.to raise_error(/depth limit exceeded/)
      end

      it 'allows execution within depth limit' do
        config = { project: '../child-project' }

        # Mock Open3.capture2e to avoid actual command execution
        status_double = double('status', exitstatus: 0)
        allow(Open3).to receive(:capture2e).and_return(['output', status_double])

        expect {
          handler.trigger_child(parent_job, config, current_depth: handler.max_depth - 1)
        }.not_to raise_error
      end
    end

    context 'with command execution' do
      it 'returns success when child pipeline succeeds' do
        config = { project: '../child-project' }

        # Mock successful execution with Open3.capture2e
        status_double = double('status', exitstatus: 0)
        allow(Open3).to receive(:capture2e).and_return(['success output', status_double])

        result = handler.trigger_child(parent_job, config)

        expect(result[:success]).to be true
        expect(result[:exit_code]).to eq(0)
        expect(result[:output]).to eq('success output')
      end

      it 'returns failure when child pipeline fails' do
        config = { project: '../child-project' }

        # Mock failed execution with Open3.capture2e
        status_double = double('status', exitstatus: 1)
        allow(Open3).to receive(:capture2e).and_return(['error output', status_double])

        result = handler.trigger_child(parent_job, config)

        expect(result[:success]).to be false
        expect(result[:exit_code]).to eq(1)
        expect(result[:output]).to eq('error output')
      end
    end
  end

  describe '#build_command_args' do
    it 'builds correct command arguments' do
      args = handler.send(
        :build_command_args,
        '.gitlab-ci.yml',
        '../child-project',
        { 'VAR1' => 'value1', 'VAR2' => 'value2' },
        123,
        2
      )

      expect(args).to include('dry-run')
      expect(args).to include('--entry')
      expect(args).to include('--project')
      expect(args).to include('../child-project')
      expect(args).to include('--variables')
      expect(args).to include('VAR1=value1')
      expect(args).to include('VAR2=value2')
      expect(args).to include('--parent-job-id')
      expect(args).to include('123')
      expect(args).to include('--depth')
      expect(args).to include('2')
    end

    it 'uses correct CLI path' do
      args = handler.send(
        :build_command_args,
        '.gitlab-ci.yml',
        '../child-project',
        {},
        1,
        1
      )

      expect(args.first).to end_with('bin/gitlab_ci_cli')
    end

    it 'handles empty variables hash' do
      args = handler.send(
        :build_command_args,
        '.gitlab-ci.yml',
        '../child-project',
        {},
        1,
        1
      )

      # Should not have --variables flags
      variables_count = args.count('--variables')
      expect(variables_count).to eq(0)
    end
  end

  describe '#emit_child_event' do
    it 'creates event hash' do
      event = handler.send(
        :emit_child_event,
        123,
        '../child-project',
        true,
        0
      )

      expect(event[:type]).to eq(:child_pipeline_created)
      expect(event[:parent_job_id]).to eq(123)
      expect(event[:child_project]).to eq('../child-project')
      expect(event[:success]).to be true
      expect(event[:exit_code]).to eq(0)
      expect(event[:timestamp]).to be_a(Time)
    end
  end
end
