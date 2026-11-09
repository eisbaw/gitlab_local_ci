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
require_relative '../../lib/mock_server'

RSpec.describe 'GitLab Integration', :integration do
  let(:server) { MockServer.new }

  describe '#create_pipeline with valid configuration' do
    let(:config) do
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
          script:
            - echo "Testing"
      YAML
    end

    it 'creates pipeline with parsed stages and jobs' do
      pipeline = server.create_pipeline(config)

      expect(pipeline).to be_a(MockPipeline)
      expect(pipeline.id).to eq(1)
      expect(pipeline.stages).to eq(['build', 'test'])

      # Jobs are now MockJob instances in an array
      expect(pipeline.jobs).to be_an(Array)
      expect(pipeline.jobs.size).to eq(2)
      expect(pipeline.jobs.map(&:name)).to include('build-job', 'test-job')
      expect(pipeline.status).to eq(MockPipeline::STATE_PENDING)
    end

    it 'emits pipeline creation event' do
      server.create_pipeline(config)

      events = server.event_queue
      expect(events.size).to eq(1)
      expect(events.first[:type]).to eq(MockServer::EVENT_PIPELINE_CREATED)
      expect(events.first[:payload][:pipeline_id]).to eq(1)
    end

    it 'increments pipeline ID for subsequent pipelines' do
      pipeline1 = server.create_pipeline(config)
      pipeline2 = server.create_pipeline(config)

      expect(pipeline1.id).to eq(1)
      expect(pipeline2.id).to eq(2)
    end
  end

  describe '#create_pipeline with needs dependencies' do
    let(:config_with_needs) do
      <<~YAML
        build:
          script: echo "build"

        test:
          script: echo "test"
          needs: [build]

        deploy:
          script: echo "deploy"
          needs: [test]
      YAML
    end

    it 'parses jobs with needs correctly' do
      pipeline = server.create_pipeline(config_with_needs)

      job_names = pipeline.jobs.map(&:name)
      expect(job_names).to include('build', 'test', 'deploy')

      test_job = pipeline.find_job('test')
      expect(test_job).not_to be_nil
      expect(test_job.needs).to be_an(Array)
      expect(test_job.needs).to include('build')
    end
  end

  describe '#create_pipeline with circular dependencies' do
    let(:circular_config) do
      <<~YAML
        job-a:
          script: echo "a"
          needs: [job-b]

        job-b:
          script: echo "b"
          needs: [job-a]
      YAML
    end

    it 'raises configuration error on circular dependency' do
      expect {
        server.create_pipeline(circular_config)
      }.to raise_error(MockServer::ConfigurationError, /circular/)
    end
  end

  describe '#create_pipeline with invalid YAML' do
    let(:invalid_config) do
      <<~YAML
        invalid-job:
          invalid_key: value
          script: []
      YAML
    end

    it 'raises configuration error with validation messages' do
      expect {
        server.create_pipeline(invalid_config)
      }.to raise_error(MockServer::ConfigurationError, /Configuration errors/)
    end
  end

  describe '#create_pipeline with malformed YAML' do
    let(:malformed_yaml) { "invalid:\n  - broken\n  indentation" }

    it 'raises configuration error for syntax errors' do
      expect {
        server.create_pipeline(malformed_yaml)
      }.to raise_error(MockServer::ConfigurationError)
    end
  end

  describe 'pipeline processing' do
    let(:simple_config) do
      <<~YAML
        build:
          script: echo "build"
      YAML
    end

    it 'processes pipeline state transitions' do
      pipeline = server.create_pipeline(simple_config)

      expect(pipeline.status).to eq(MockPipeline::STATE_PENDING)

      # Manually transition first job to running (simulates what DryRunCommand does)
      pipeline.jobs.first.transition_to(MockJob::STATUS_RUNNING)

      # Now process_pipeline should detect the state change
      changed = server.process_pipeline(pipeline)
      expect(changed).to be true
      expect(pipeline.status).to eq(MockPipeline::STATE_RUNNING)
    end

    it 'emits pipeline started event on transition to running' do
      pipeline = server.create_pipeline(simple_config)
      server.event_queue.clear

      # Manually transition first job to running (simulates what DryRunCommand does)
      pipeline.jobs.first.transition_to(MockJob::STATUS_RUNNING)

      server.process_pipeline(pipeline)

      events = server.event_queue
      expect(events.last[:type]).to eq(MockServer::EVENT_PIPELINE_STARTED)
    end
  end

  describe '#has_pending_jobs?' do
    let(:config) do
      <<~YAML
        build:
          script: echo "build"
      YAML
    end

    it 'returns true for newly created pipeline' do
      pipeline = server.create_pipeline(config)
      expect(server.has_pending_jobs?(pipeline)).to be true
    end
  end

  describe '#pending_jobs' do
    let(:config_with_stages) do
      <<~YAML
        stages:
          - build
          - test

        build:
          stage: build
          script: echo "build"

        test:
          stage: test
          script: echo "test"
      YAML
    end

    it 'returns jobs from first stage initially' do
      pipeline = server.create_pipeline(config_with_stages)
      pending = server.pending_jobs(pipeline)

      expect(pending.size).to be > 0
      expect(pending.first.name).to eq('build')
    end
  end
end
