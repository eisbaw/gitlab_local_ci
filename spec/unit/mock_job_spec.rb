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
require 'mock_job'

RSpec.describe MockJob do
  let(:basic_job_data) do
    {
      'id' => 1,
      'name' => 'test_job',
      'stage' => 'test',
      'script' => ['echo "Running tests"', 'bundle exec rspec'],
      'image' => 'ruby:3.0',
      'services' => ['postgres:13'],
      'artifacts' => { 'paths' => ['coverage/'] },
      'variables' => { 'ENV' => 'test', 'DEBUG' => 'true' },
      'tags' => ['docker', 'linux']
    }
  end

  describe '#initialize' do
    it 'should initialize with hash using string keys' do
      job = described_class.new(basic_job_data)

      expect(job.id).to eq(1)
      expect(job.name).to eq('test_job')
      expect(job.stage).to eq('test')
      expect(job.script).to eq(['echo "Running tests"', 'bundle exec rspec'])
      expect(job.image).to eq('ruby:3.0')
      expect(job.services).to eq(['postgres:13'])
      expect(job.artifacts).to eq({ 'paths' => ['coverage/'] })
      expect(job.variables).to eq({ 'ENV' => 'test', 'DEBUG' => 'true' })
      expect(job.tag_list).to eq(['docker', 'linux'])
      expect(job.status).to eq(MockJob::STATUS_PENDING)
    end

    it 'should initialize with hash using symbol keys' do
      data = {
        id: 2,
        name: 'build_job',
        stage: 'build',
        script: ['npm run build']
      }

      job = described_class.new(data)

      expect(job.id).to eq(2)
      expect(job.name).to eq('build_job')
      expect(job.stage).to eq('build')
      expect(job.script).to eq(['npm run build'])
    end

    it 'should default script to empty array when not provided' do
      data = { 'id' => 1, 'name' => 'test' }

      job = described_class.new(data)

      expect(job.script).to eq([])
    end

    it 'should default services to empty array when not provided' do
      data = { 'id' => 1, 'name' => 'test' }

      job = described_class.new(data)

      expect(job.services).to eq([])
    end

    it 'should default variables to empty hash when not provided' do
      data = { 'id' => 1, 'name' => 'test' }

      job = described_class.new(data)

      expect(job.variables).to eq({})
    end

    it 'should default tag_list to empty array when not provided' do
      data = { 'id' => 1, 'name' => 'test' }

      job = described_class.new(data)

      expect(job.tag_list).to eq([])
    end

    it 'should accept tags as tag_list' do
      data = { 'id' => 1, 'name' => 'test', 'tag_list' => ['docker'] }

      job = described_class.new(data)

      expect(job.tag_list).to eq(['docker'])
    end

    it 'should accept tags field as alternative to tag_list' do
      data = { 'id' => 1, 'name' => 'test', 'tags' => ['shell'] }

      job = described_class.new(data)

      expect(job.tag_list).to eq(['shell'])
    end

    it 'should default needs to empty array when not provided' do
      data = { 'id' => 1, 'name' => 'test' }

      job = described_class.new(data)

      expect(job.needs).to eq([])
    end

    it 'should initialize status to pending' do
      job = described_class.new(basic_job_data)

      expect(job.status).to eq(MockJob::STATUS_PENDING)
    end

    it 'should handle nil image' do
      data = basic_job_data.merge('image' => nil)

      job = described_class.new(data)

      expect(job.image).to be_nil
    end

    it 'should handle nil artifacts' do
      data = basic_job_data.merge('artifacts' => nil)

      job = described_class.new(data)

      expect(job.artifacts).to be_nil
    end

    it 'should handle minimal job data' do
      minimal = { 'id' => 1, 'name' => 'minimal' }

      job = described_class.new(minimal)

      expect(job.id).to eq(1)
      expect(job.name).to eq('minimal')
      expect(job.status).to eq(MockJob::STATUS_PENDING)
    end

    it 'should handle needs as array of strings' do
      data = basic_job_data.merge('needs' => ['build_job', 'lint_job'])

      job = described_class.new(data)

      expect(job.needs).to eq(['build_job', 'lint_job'])
    end

    it 'should handle needs as array of hashes' do
      data = basic_job_data.merge('needs' => [{ 'job' => 'build_job' }])

      job = described_class.new(data)

      expect(job.needs).to eq([{ 'job' => 'build_job' }])
    end
  end

  describe '#transition_to' do
    let(:job) { described_class.new(basic_job_data) }

    context 'valid transitions' do
      it 'should transition from pending to running' do
        result = job.transition_to(MockJob::STATUS_RUNNING)

        expect(result).to be true
        expect(job.status).to eq(MockJob::STATUS_RUNNING)
      end

      it 'should transition from running to completed' do
        job.instance_variable_set(:@status, MockJob::STATUS_RUNNING)

        result = job.transition_to(MockJob::STATUS_COMPLETED)

        expect(result).to be true
        expect(job.status).to eq(MockJob::STATUS_COMPLETED)
      end

      it 'should transition from running to failed' do
        job.instance_variable_set(:@status, MockJob::STATUS_RUNNING)

        result = job.transition_to(MockJob::STATUS_FAILED)

        expect(result).to be true
        expect(job.status).to eq(MockJob::STATUS_FAILED)
      end

      it 'should reject invalid state transition from pending to completed' do
        expect do
          job.transition_to(MockJob::STATUS_COMPLETED)
        end.to raise_error(ArgumentError, /invalid transition/)
      end

      it 'should reject transition from completed to running' do
        job.instance_variable_set(:@status, MockJob::STATUS_COMPLETED)

        expect do
          job.transition_to(MockJob::STATUS_RUNNING)
        end.to raise_error(ArgumentError, /invalid transition/)
      end

      it 'should allow transition from any state to canceled' do
        # Cancellation should be allowed from any state
        [MockJob::STATUS_PENDING, MockJob::STATUS_RUNNING].each do |status|
          test_job = described_class.new(basic_job_data)
          test_job.instance_variable_set(:@status, status)

          result = test_job.transition_to(MockJob::STATUS_CANCELED)

          expect(result).to be true
          expect(test_job.status).to eq(MockJob::STATUS_CANCELED)
        end
      end

      it 'should allow transition to skipped from pending' do
        result = job.transition_to(MockJob::STATUS_SKIPPED)

        expect(result).to be true
        expect(job.status).to eq(MockJob::STATUS_SKIPPED)
      end

      it 'should handle transition to same state as no-op' do
        result = job.transition_to(MockJob::STATUS_PENDING)

        expect(result).to be true
        expect(job.status).to eq(MockJob::STATUS_PENDING)
      end

      it 'should handle unknown status with error' do
        expect do
          job.transition_to(:unknown_status)
        end.to raise_error(ArgumentError, /unknown status/)
      end
    end
  end

  describe 'status predicates' do
    let(:job) { described_class.new(basic_job_data) }

    describe '#pending?' do
      it 'should return true when status is pending' do
        expect(job.pending?).to be true
      end

      it 'should return false when status is not pending' do
        job.instance_variable_set(:@status, MockJob::STATUS_RUNNING)

        expect(job.pending?).to be false
      end
    end

    describe '#running?' do
      it 'should return false when status is pending' do
        expect(job.running?).to be false
      end

      it 'should return true when status is running' do
        job.instance_variable_set(:@status, MockJob::STATUS_RUNNING)

        expect(job.running?).to be true
      end
    end

    describe '#completed?' do
      it 'should return false when status is pending' do
        expect(job.completed?).to be false
      end

      it 'should return false when status is running' do
        job.instance_variable_set(:@status, MockJob::STATUS_RUNNING)

        expect(job.completed?).to be false
      end

      it 'should return true when status is completed' do
        job.instance_variable_set(:@status, MockJob::STATUS_COMPLETED)

        expect(job.completed?).to be true
      end
    end

    describe '#failed?' do
      it 'should return false when status is not failed' do
        expect(job.failed?).to be false
      end

      it 'should return true when status is failed' do
        job.instance_variable_set(:@status, MockJob::STATUS_FAILED)

        expect(job.failed?).to be true
      end
    end

    describe '#canceled?' do
      it 'should return false when status is not canceled' do
        expect(job.canceled?).to be false
      end

      it 'should return true when status is canceled' do
        job.instance_variable_set(:@status, MockJob::STATUS_CANCELED)

        expect(job.canceled?).to be true
      end
    end

    describe '#skipped?' do
      it 'should return false when status is not skipped' do
        expect(job.skipped?).to be false
      end

      it 'should return true when status is skipped' do
        job.instance_variable_set(:@status, MockJob::STATUS_SKIPPED)

        expect(job.skipped?).to be true
      end
    end

    describe '#finished?' do
      it 'should return false when status is pending' do
        expect(job.finished?).to be false
      end

      it 'should return false when status is running' do
        job.instance_variable_set(:@status, MockJob::STATUS_RUNNING)

        expect(job.finished?).to be false
      end

      it 'should return true when status is completed' do
        job.instance_variable_set(:@status, MockJob::STATUS_COMPLETED)

        expect(job.finished?).to be true
      end

      it 'should return true when status is failed' do
        job.instance_variable_set(:@status, MockJob::STATUS_FAILED)

        expect(job.finished?).to be true
      end

      it 'should return true when status is canceled' do
        job.instance_variable_set(:@status, MockJob::STATUS_CANCELED)

        expect(job.finished?).to be true
      end

      it 'should return true when status is skipped' do
        job.instance_variable_set(:@status, MockJob::STATUS_SKIPPED)

        expect(job.finished?).to be true
      end
    end

    describe 'predicate method consistency' do
      it 'should have exactly one status predicate true at a time' do
        statuses = [
          MockJob::STATUS_PENDING,
          MockJob::STATUS_RUNNING,
          MockJob::STATUS_COMPLETED,
          MockJob::STATUS_FAILED,
          MockJob::STATUS_CANCELED,
          MockJob::STATUS_SKIPPED
        ]

        statuses.each do |status|
          test_job = described_class.new(basic_job_data)
          test_job.instance_variable_set(:@status, status)

          predicates = [
            test_job.pending?,
            test_job.running?,
            test_job.completed?,
            test_job.failed?,
            test_job.canceled?,
            test_job.skipped?
          ]

          # Exactly one should be true
          expect(predicates.count(true)).to eq(1)
        end
      end

      it 'should have finished? true for all terminal states' do
        terminal_statuses = [
          MockJob::STATUS_COMPLETED,
          MockJob::STATUS_FAILED,
          MockJob::STATUS_CANCELED,
          MockJob::STATUS_SKIPPED
        ]

        terminal_statuses.each do |status|
          test_job = described_class.new(basic_job_data)
          test_job.instance_variable_set(:@status, status)

          expect(test_job.finished?).to be true
        end
      end

      it 'should have finished? false for non-terminal states' do
        non_terminal_statuses = [
          MockJob::STATUS_PENDING,
          MockJob::STATUS_RUNNING
        ]

        non_terminal_statuses.each do |status|
          test_job = described_class.new(basic_job_data)
          test_job.instance_variable_set(:@status, status)

          expect(test_job.finished?).to be false
        end
      end
    end
  end

  describe 'status constants' do
    it 'should define all required status constants' do
      expect(MockJob::STATUS_PENDING).to eq(:pending)
      expect(MockJob::STATUS_RUNNING).to eq(:running)
      expect(MockJob::STATUS_COMPLETED).to eq(:completed)
      expect(MockJob::STATUS_FAILED).to eq(:failed)
      expect(MockJob::STATUS_CANCELED).to eq(:canceled)
      expect(MockJob::STATUS_SKIPPED).to eq(:skipped)
    end

    it 'should have unique status constants' do
      statuses = [
        MockJob::STATUS_PENDING,
        MockJob::STATUS_RUNNING,
        MockJob::STATUS_COMPLETED,
        MockJob::STATUS_FAILED,
        MockJob::STATUS_CANCELED,
        MockJob::STATUS_SKIPPED
      ]

      expect(statuses.uniq.size).to eq(statuses.size)
    end
  end

  describe 'edge cases' do
    it 'should handle job with very long script array' do
      long_script = Array.new(1000) { |i| "echo 'Step #{i}'" }
      data = basic_job_data.merge('script' => long_script)

      job = described_class.new(data)

      expect(job.script.size).to eq(1000)
    end

    it 'should handle job with empty strings in script' do
      data = basic_job_data.merge('script' => ['', 'echo "test"', ''])

      job = described_class.new(data)

      expect(job.script).to eq(['', 'echo "test"', ''])
    end

    it 'should handle job with many tags' do
      many_tags = Array.new(50) { |i| "tag_#{i}" }
      data = basic_job_data.merge('tags' => many_tags)

      job = described_class.new(data)

      expect(job.tag_list.size).to eq(50)
    end

    it 'should handle job with duplicate tags' do
      data = basic_job_data.merge('tags' => ['docker', 'docker', 'linux'])

      job = described_class.new(data)

      # Implementation might deduplicate or keep duplicates
      expect(job.tag_list).to include('docker', 'linux')
    end

    it 'should handle job with complex nested variables' do
      complex_vars = {
        'SIMPLE' => 'value',
        'NESTED' => { 'key' => 'value' },
        'ARRAY' => [1, 2, 3]
      }
      data = basic_job_data.merge('variables' => complex_vars)

      job = described_class.new(data)

      expect(job.variables).to eq(complex_vars)
    end

    it 'should handle job with nil name' do
      data = basic_job_data.merge('name' => nil)

      job = described_class.new(data)

      expect(job.name).to be_nil
    end

    it 'should handle job with numeric id' do
      data = basic_job_data.merge('id' => 12345)

      job = described_class.new(data)

      expect(job.id).to eq(12345)
    end

    it 'should handle job with string id' do
      data = basic_job_data.merge('id' => '12345')

      job = described_class.new(data)

      expect(job.id).to eq('12345')
    end

    it 'should handle job with uuid as id' do
      uuid = 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
      data = basic_job_data.merge('id' => uuid)

      job = described_class.new(data)

      expect(job.id).to eq(uuid)
    end
  end
end

RSpec.describe MockJob, 'scheduling attributes' do
  it 'defaults to a stage-scheduled on_success job that may not fail' do
    job = described_class.new('name' => 'j')

    expect([job.scheduling_type, job.dag?, job.when_to_run, job.allow_failure]).to eq([:stage, false, 'on_success', false])
  end

  it 'rejects an unknown when: or scheduling_type' do
    expect { described_class.new('name' => 'j', 'when' => 'never') }.to raise_error(ArgumentError, /unknown when: 'never'/)
    expect { described_class.new('name' => 'j', 'scheduling_type' => :x) }.to raise_error(ArgumentError, /scheduling_type/)
  end
end

# run records real exit codes (TASK-22).
RSpec.describe MockJob, 'exit codes' do
  def finished(allow_failure, exit_code)
    job = described_class.new('name' => 'j', 'allow_failure' => allow_failure)
    job.transition_to(MockJob::STATUS_RUNNING)
    job.finish(exit_code)
    job
  end

  it 'completes on 0 and fails otherwise, keeping the code' do
    expect([finished(nil, 0).status, finished(nil, 3).status, finished(nil, 3).exit_code])
      .to eq([MockJob::STATUS_COMPLETED, MockJob::STATUS_FAILED, 3])
  end

  it 'allows a failure with allow_failure: true whatever the code' do
    expect(finished(true, 3).allow_failure).to be(true)
  end

  it 'allows only listed codes with allow_failure: {exit_codes:} (Integer or list)' do
    expect(finished({ 'exit_codes' => [3, 4] }, 4).allow_failure).to be(true)
    expect(finished({ 'exit_codes' => 3 }, 3).allow_failure).to be(true)
    expect(finished({ 'exit_codes' => [3] }, 5).allow_failure).to be(false)
  end

  it 'does not allow failure by exit_codes before a code exists (the simulator)' do
    expect(described_class.new('name' => 'j', 'allow_failure' => { 'exit_codes' => [1] }).allow_failure).to be(false)
  end

  it 'refuses finish on a job that is not running, or a non-Integer code' do
    expect { described_class.new('name' => 'j').finish(0) }.to raise_error(ArgumentError, /not running/)
    job = described_class.new('name' => 'j')
    job.transition_to(MockJob::STATUS_RUNNING)
    expect { job.finish('0') }.to raise_error(ArgumentError, /Integer/)
  end
end
