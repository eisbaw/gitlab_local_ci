# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
require 'spec_helper'
require 'mock_pipeline'

# Job ordering, as upstream AtomicProcessingService + ProcessBuildService
# decide it (TASK-7). Behaviour is observed through waves: each wave skips
# what is blocked, starts every job that may start, then finishes them all
# with the outcome the example chooses.
RSpec.describe MockPipeline do
  def pipeline_for(jobs, stages: %w[build test deploy])
    described_class.new(id: 1, stages: stages, jobs: jobs, ref: 'main', variables: {})
  end

  # @param fail [Array<String>] jobs that fail instead of succeeding
  # @return [Hash] job name => wave it started in, or :skipped
  def waves(pipeline, fail: [])
    started = {}
    (pipeline.jobs.size + 1).times do |wave|
      pipeline.skip_blocked_jobs.each { |job| started[job.name] = :skipped }
      ready = pipeline.pending_jobs
      break if ready.empty?

      ready.each do |job|
        job.transition_to(MockJob::STATUS_RUNNING)
        started[job.name] = wave
      end
      ready.each { |job| job.transition_to(fail.include?(job.name) ? MockJob::STATUS_FAILED : MockJob::STATUS_COMPLETED) }
    end
    expect(pipeline.jobs).to all(be_finished)
    started
  end

  let(:three_stages_and_dag) do
    {
      'build_a' => { 'stage' => 'build', 'script' => 'a' },
      'build_b' => { 'stage' => 'build', 'script' => 'b' },
      'test' => { 'stage' => 'test', 'script' => 't' },
      'after_a' => { 'stage' => 'deploy', 'script' => 'x', 'needs' => ['build_a'] },
      'independent' => { 'stage' => 'deploy', 'script' => 'i', 'needs' => [] },
      'deploy' => { 'stage' => 'deploy', 'script' => 'd' }
    }
  end

  describe 'stage and needs ordering' do
    it 'starts a job without needs only after every earlier stage, needs: [] at once, needs: [x] after x' do
      expect(waves(pipeline_for(three_stages_and_dag))).to eq(
        'build_a' => 0, 'build_b' => 0, 'independent' => 0,
        'test' => 1, 'after_a' => 1,
        'deploy' => 2
      )
    end

    it 'waits for every job of every earlier stage, not only the previous stage' do
      pipeline = pipeline_for(three_stages_and_dag)
      pipeline.find_job('build_b').transition_to(MockJob::STATUS_RUNNING)
      %w[build_a test].each do |name|
        job = pipeline.find_job(name)
        job.transition_to(MockJob::STATUS_RUNNING)
        job.transition_to(MockJob::STATUS_COMPLETED)
      end

      expect(pipeline.pending_jobs.map(&:name)).to contain_exactly('after_a', 'independent')
    end

    it 'reads the job: key of map-form needs (TASK-15)' do
      jobs = three_stages_and_dag.merge('after_a' => { 'stage' => 'deploy', 'script' => 'x', 'needs' => [{ 'job' => 'build_a' }] })

      expect(waves(pipeline_for(jobs))['after_a']).to eq(1)
      expect(pipeline_for(jobs).find_job('after_a').needs).to eq(['build_a'])
    end

    it 'drops an optional need on a job not in the pipeline and ignores cross-pipeline needs' do
      jobs = {
        'build' => { 'stage' => 'build', 'script' => 'b' },
        'deploy' => {
          'stage' => 'deploy', 'script' => 'd',
          'needs' => [{ 'job' => 'gone', 'optional' => true },
                      { 'pipeline' => '$PARENT_PIPELINE_ID', 'job' => 'build' },
                      { 'project' => 'g/p', 'job' => 'build', 'ref' => 'main' }]
        }
      }

      expect(pipeline_for(jobs).find_job('deploy').needs).to eq([])
      expect(waves(pipeline_for(jobs))['deploy']).to eq(0)
    end

    it 'rejects a required need on a job not in the pipeline' do
      jobs = { 'deploy' => { 'stage' => 'deploy', 'script' => 'd', 'needs' => [{ 'job' => 'gone' }] } }

      expect { pipeline_for(jobs) }.to raise_error(ArgumentError, /invalid need 'gone'/)
    end

    it 'puts a job without stage: in test and rejects a stage not in stages' do
      expect(pipeline_for({ 'j' => { 'script' => 'x' } }).find_job('j').stage).to eq('test')
      expect { pipeline_for({ 'j' => { 'stage' => '.pre', 'script' => 'x' } }) }
        .to raise_error(ArgumentError, /stage '\.pre', not in stages/)
    end
  end

  describe 'failures' do
    it 'skips later stages and DAG dependents after a failure, but not needs: [] jobs' do
      result = waves(pipeline_for(three_stages_and_dag), fail: ['build_a'])

      expect(result).to eq(
        'build_a' => 0, 'build_b' => 0, 'independent' => 0,
        'test' => :skipped, 'after_a' => :skipped, 'deploy' => :skipped
      )
    end

    it 'lets a stage job run after skipped jobs when nothing failed further back' do
      # deploy's earlier stages hold only success and skipped: upstream
      # on_success accepts [success skipped] for stage jobs.
      jobs = {
        'build' => { 'stage' => 'build', 'script' => 'b' },
        'only_on_failure' => { 'stage' => 'test', 'script' => 'f', 'when' => 'on_failure' },
        'deploy' => { 'stage' => 'deploy', 'script' => 'd' }
      }

      expect(waves(pipeline_for(jobs))).to eq('build' => 0, 'only_on_failure' => :skipped, 'deploy' => 1)
    end

    it 'skips a DAG job whose need was skipped' do
      jobs = {
        'build' => { 'stage' => 'build', 'script' => 'b' },
        'only_on_failure' => { 'stage' => 'test', 'script' => 'f', 'when' => 'on_failure' },
        'after' => { 'stage' => 'deploy', 'script' => 'd', 'needs' => ['only_on_failure'] }
      }

      expect(waves(pipeline_for(jobs))).to eq('build' => 0, 'only_on_failure' => :skipped, 'after' => :skipped)
    end

    it 'treats an allow_failure failure as success' do
      jobs = three_stages_and_dag.merge('build_a' => { 'stage' => 'build', 'script' => 'a', 'allow_failure' => true })

      expect(waves(pipeline_for(jobs), fail: ['build_a'])).to eq(
        'build_a' => 0, 'build_b' => 0, 'independent' => 0, 'test' => 1, 'after_a' => 1, 'deploy' => 2
      )
    end

    it 'does not treat allow_failure: {exit_codes: ...} as allowing an arbitrary failure' do
      jobs = three_stages_and_dag.merge('build_a' => { 'stage' => 'build', 'script' => 'a', 'allow_failure' => { 'exit_codes' => [3] } })

      expect(waves(pipeline_for(jobs), fail: ['build_a'])['test']).to eq(:skipped)
    end

    it 'runs on_failure jobs only after a failure and always jobs either way' do
      jobs = {
        'build' => { 'stage' => 'build', 'script' => 'b' },
        'notify' => { 'stage' => 'test', 'script' => 'n', 'when' => 'on_failure' },
        'cleanup' => { 'stage' => 'test', 'script' => 'c', 'when' => 'always' }
      }

      expect(waves(pipeline_for(jobs))).to eq('build' => 0, 'notify' => :skipped, 'cleanup' => 1)
      expect(waves(pipeline_for(jobs), fail: ['build'])).to eq('build' => 0, 'notify' => 1, 'cleanup' => 1)
    end
  end

  describe '#status' do
    it 'is pending, then running, then the composite of the finished jobs' do
      pipeline = pipeline_for(three_stages_and_dag)
      expect(pipeline.status).to eq(MockPipeline::STATE_PENDING)

      pipeline.find_job('build_a').transition_to(MockJob::STATUS_RUNNING)
      expect(pipeline.status).to eq(MockPipeline::STATE_RUNNING)
    end

    it 'is success with skipped jobs and failed after an unallowed failure' do
      jobs = { 'build' => { 'stage' => 'build', 'script' => 'b' },
               'notify' => { 'stage' => 'test', 'script' => 'n', 'when' => 'on_failure' } }
      green = pipeline_for(jobs)
      waves(green)
      expect(green.status).to eq(MockPipeline::STATE_SUCCESS)

      red = pipeline_for(three_stages_and_dag)
      waves(red, fail: ['build_a'])
      expect(red.status).to eq(MockPipeline::STATE_FAILED)
    end
  end
end
