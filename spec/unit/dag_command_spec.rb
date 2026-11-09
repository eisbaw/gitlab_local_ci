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
require 'commands/dag_command'
require 'tempfile'

RSpec.describe DagCommand do
  describe '#execute' do
    context 'with valid pipeline configuration' do
      let(:config_content) do
        <<~YAML
          stages:
            - build
            - test
            - deploy

          build-job:
            stage: build
            script:
              - echo "Building"

          test-job:
            stage: test
            needs:
              - build-job
            script:
              - echo "Testing"

          deploy-job:
            stage: deploy
            needs:
              - test-job
            script:
              - echo "Deploying"
        YAML
      end

      it 'generates valid DOT format output' do
        config_file = Tempfile.new(['test-config', '.yml'])
        config_file.write(config_content)
        config_file.close

        command = DagCommand.new(entry: config_file.path)
        output = command.execute

        expect(output).to include('digraph pipeline {')
        expect(output).to include('rankdir="LR"')
        expect(output).to include('subgraph cluster_build')
        expect(output).to include('subgraph cluster_test')
        expect(output).to include('subgraph cluster_deploy')
        expect(output).to include('}')

        config_file.unlink
      end

      it 'includes all job nodes' do
        config_file = Tempfile.new(['test-config', '.yml'])
        config_file.write(config_content)
        config_file.close

        command = DagCommand.new(entry: config_file.path)
        output = command.execute

        expect(output).to include('build_job')
        expect(output).to include('test_job')
        expect(output).to include('deploy_job')

        config_file.unlink
      end

      it 'includes dependency edges' do
        config_file = Tempfile.new(['test-config', '.yml'])
        config_file.write(config_content)
        config_file.close

        command = DagCommand.new(entry: config_file.path)
        output = command.execute

        expect(output).to include('build_job -> test_job')
        expect(output).to include('test_job -> deploy_job')

        config_file.unlink
      end
    end

    context 'with circular dependencies' do
      let(:circular_config) do
        <<~YAML
          stages:
            - test

          job-a:
            stage: test
            needs:
              - job-b
            script:
              - echo "Job A"

          job-b:
            stage: test
            needs:
              - job-a
            script:
              - echo "Job B"
        YAML
      end

      it 'raises CircularDependencyError' do
        config_file = Tempfile.new(['circular-config', '.yml'])
        config_file.write(circular_config)
        config_file.close

        command = DagCommand.new(entry: config_file.path)

        expect { command.execute }.to raise_error(
          DagCommand::CircularDependencyError,
          /Circular dependency detected/
        )

        config_file.unlink
      end
    end

    context 'with invalid YAML' do
      let(:invalid_yaml) do
        <<~YAML
          stages:
            - build

          build-job:
            stage: build
            script: [unclosed bracket
        YAML
      end

      it 'raises InvalidConfigError' do
        config_file = Tempfile.new(['invalid-config', '.yml'])
        config_file.write(invalid_yaml)
        config_file.close

        command = DagCommand.new(entry: config_file.path)

        # Same message lint and dry-run print (PipelineBuilder.load_yaml)
        expect { command.execute }.to raise_error(
          DagCommand::InvalidConfigError,
          /YAML syntax error/
        )

        config_file.unlink
      end
    end

    context 'with missing configuration file' do
      it 'raises InvalidConfigError naming the file' do
        command = DagCommand.new(entry: '/nonexistent/path/config.yml')

        expect { command.execute }.to raise_error(
          DagCommand::InvalidConfigError,
          %r{File not found: /nonexistent/path/config.yml}
        )
      end
    end

    context 'with complex needs relationships' do
      let(:complex_config) do
        <<~YAML
          stages:
            - build
            - test
            - deploy

          build-frontend:
            stage: build
            script:
              - echo "Building frontend"

          build-backend:
            stage: build
            script:
              - echo "Building backend"

          test-unit:
            stage: test
            needs:
              - build-backend
            script:
              - echo "Running unit tests"

          test-integration:
            stage: test
            needs:
              - build-frontend
              - build-backend
            script:
              - echo "Running integration tests"

          deploy-staging:
            stage: deploy
            needs:
              - test-unit
              - test-integration
            script:
              - echo "Deploying to staging"
        YAML
      end

      it 'generates DAG with multiple dependency edges' do
        config_file = Tempfile.new(['complex-config', '.yml'])
        config_file.write(complex_config)
        config_file.close

        command = DagCommand.new(entry: config_file.path)
        output = command.execute

        # Check that all nodes are present
        expect(output).to include('build_frontend')
        expect(output).to include('build_backend')
        expect(output).to include('test_unit')
        expect(output).to include('test_integration')
        expect(output).to include('deploy_staging')

        # Check dependency edges
        expect(output).to include('build_backend -> test_unit')
        expect(output).to include('build_frontend -> test_integration')
        expect(output).to include('build_backend -> test_integration')
        expect(output).to include('test_unit -> deploy_staging')
        expect(output).to include('test_integration -> deploy_staging')

        config_file.unlink
      end
    end

    context 'with needs in hash format' do
      let(:hash_needs_config) do
        <<~YAML
          stages:
            - build
            - test

          build-job:
            stage: build
            script:
              - echo "Building"

          test-job:
            stage: test
            needs:
              - job: build-job
                artifacts: true
            script:
              - echo "Testing"
        YAML
      end

      it 'correctly extracts job names from hash format needs' do
        config_file = Tempfile.new(['hash-needs-config', '.yml'])
        config_file.write(hash_needs_config)
        config_file.close

        command = DagCommand.new(entry: config_file.path)
        output = command.execute

        expect(output).to include('build_job -> test_job')

        config_file.unlink
      end
    end

    context 'with jobs without explicit stage' do
      let(:default_stage_config) do
        <<~YAML
          stages:
            - build
            - test

          job-without-stage:
            script:
              - echo "Default stage job"
        YAML
      end

      it 'assigns jobs to default test stage' do
        config_file = Tempfile.new(['default-stage-config', '.yml'])
        config_file.write(default_stage_config)
        config_file.close

        command = DagCommand.new(entry: config_file.path)
        output = command.execute

        expect(output).to include('subgraph cluster_test')
        expect(output).to include('job_without_stage')

        config_file.unlink
      end
    end

    context 'with special characters in job names' do
      let(:special_chars_config) do
        <<~YAML
          stages:
            - test

          test:job-name:
            stage: test
            script:
              - echo "Job with special chars"
        YAML
      end

      it 'sanitizes job names for DOT format' do
        config_file = Tempfile.new(['special-chars-config', '.yml'])
        config_file.write(special_chars_config)
        config_file.close

        command = DagCommand.new(entry: config_file.path)
        output = command.execute

        # Colons should be replaced with underscores
        expect(output).to include('test_job_name')

        config_file.unlink
      end
    end
  end

  describe 'private methods' do
    let(:command) { DagCommand.new }

    describe '#sanitize_id' do
      it 'replaces special characters with underscores' do
        expect(command.send(:sanitize_id, 'job-name')).to eq('job_name')
        expect(command.send(:sanitize_id, 'job:name')).to eq('job_name')
        expect(command.send(:sanitize_id, 'job.name')).to eq('job_name')
        expect(command.send(:sanitize_id, 'job name')).to eq('job_name')
      end

      it 'preserves alphanumeric characters and underscores' do
        expect(command.send(:sanitize_id, 'job_name_123')).to eq('job_name_123')
      end
    end

    describe '#escape_label' do
      it 'escapes quotes in labels' do
        expect(command.send(:escape_label, 'job "quoted"')).to eq('job \\"quoted\\"')
      end

      it 'escapes backslashes in labels' do
        # Ruby string literal: single backslash becomes escaped
        expect(command.send(:escape_label, 'job\name')).to eq('job\\name')
      end
    end
  end
end
