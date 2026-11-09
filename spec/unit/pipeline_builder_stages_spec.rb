# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'spec_helper'
require 'tmpdir'
require 'pipeline_builder'

# .pre/.post edge stages and the stage check (TASK-17, TASK-50).
# Reference: gitlab/lib/gitlab/ci/config/stages.rb (wrap_with_edge_stages),
# gitlab/lib/gitlab/ci/config/entry/stages.rb (default),
# gitlab/lib/gitlab/ci/yaml_processor.rb#validate_job_stage!,
# gitlab/lib/gitlab/ci/pipeline/chain/populate.rb#no_pipeline_to_create?,
# gitlab/spec/services/ci/create_pipeline_service/pre_post_stages_spec.rb.
RSpec.describe PipelineBuilder do
  around do |example|
    Dir.mktmpdir('pipeline_stages') do |dir|
      @dir = dir
      example.run
    end
  end

  def build(yaml, variables: {})
    File.write(File.join(@dir, '.gitlab-ci.yml'), yaml)
    context = PinnedPipelineContext.context(@dir, variables: variables)
    PipelineBuilder.build(File.join(@dir, '.gitlab-ci.yml'), context)
  end

  def built(yaml, **opts)
    result = build(yaml, **opts)
    raise "unexpected errors: #{result.errors}" unless result.ok?

    result
  end

  describe '.stages' do
    it 'is .pre build test deploy .post when stages: is absent' do
      expect(described_class.stages({})).to eq(%w[.pre build test deploy .post])
    end

    it 'puts .pre first and .post last around the declared stages' do
      expect(described_class.stages({ 'stages' => %w[build test] })).to eq(%w[.pre build test .post])
    end

    it 'moves .pre/.post listed elsewhere to the edges' do
      expect(described_class.stages({ 'stages' => %w[a .post b .pre] })).to eq(%w[.pre a b .post])
    end

    it 'leaves an empty list alone, as upstream inject_edge_stages! does' do
      expect(described_class.stages({ 'stages' => [] })).to eq([])
    end
  end

  describe 'stage check' do
    it 'accepts .pre/.post without declaring them' do
      result = built(<<~YAML)
        stages: [build]
        first:
          stage: .pre
          script: [echo]
        b:
          stage: build
          script: [echo]
        last:
          stage: .post
          script: [echo]
      YAML
      expect(result.stages).to eq(%w[.pre build .post])
      expect(result.pipeline_jobs.keys).to eq(%w[first b last])
    end

    it 'rejects an undeclared stage in upstream wording' do
      result = build(<<~YAML)
        stages: [build]
        deploy_job:
          stage: production
          script: [echo]
      YAML
      expect(result.errors).to eq(
        ['deploy_job job: chosen stage production does not exist; available stages are .pre, build, .post']
      )
    end

    it 'checks the default stage test of a job without stage: too' do
      result = build("stages: [build]\nj:\n  script: [echo]\n")
      expect(result.errors).to eq(['j job: chosen stage test does not exist; available stages are .pre, build, .post'])
    end

    it 'does not check hidden templates (not jobs upstream)' do
      result = built("stages: [build]\n.t:\n  stage: nowhere\nb:\n  stage: build\n  script: [echo]\n")
      expect(result.pipeline_jobs.keys).to eq(%w[b])
    end

    it 'checks the stage a job got from extends' do
      result = build("stages: [build]\n.t:\n  stage: nowhere\nj:\n  extends: .t\n  script: [echo]\n")
      expect(result.errors.first).to start_with('j job: chosen stage nowhere does not exist')
    end

    it 'rejects a stages: that is not a list of strings' do
      result = build("stages: build\nj:\n  stage: build\n  script: [echo]\n")
      expect(result.errors).to eq(
        ['stages config should be an array of strings or a nested array of strings up to 10 levels deep']
      )
    end
  end

  # Upstream pre_post_stages_spec, verbatim config.
  describe 'a pipeline with jobs only in .pre/.post' do
    let(:yaml) do
      <<~YAML
        validate:
          stage: .pre
          script: echo Hello World

        build:
          stage: build
          rules:
            - if: $CI_COMMIT_BRANCH == "master"
          script: echo Hello World

        notify:
          stage: .post
          script: echo Hello World
      YAML
    end

    it 'is created when another job is in it' do
      result = built(yaml, variables: { 'CI_COMMIT_BRANCH' => 'master' })
      expect(result.pipeline_jobs.keys).to contain_exactly('validate', 'build', 'notify')
    end

    it 'is not created when rules leave only .pre/.post jobs' do
      result = built(yaml, variables: { 'CI_COMMIT_BRANCH' => 'feature' })
      expect(result.pipeline_jobs).to eq({})
      expect(result.excluded_jobs['build']).to eq('no rule matched')
      expect(result.excluded_jobs['validate']).to eq(PipelineBuilder::ONLY_EDGE_STAGE_JOBS_MESSAGE)
      expect(result.excluded_jobs['notify']).to eq(PipelineBuilder::ONLY_EDGE_STAGE_JOBS_MESSAGE)
    end

    it 'is not created when the config has only .pre/.post jobs' do
      result = built("a:\n  stage: .pre\n  script: [echo]\n")
      expect(result.pipeline_jobs).to eq({})
      expect(result.excluded_jobs).to eq('a' => PipelineBuilder::ONLY_EDGE_STAGE_JOBS_MESSAGE)
    end
  end
end
