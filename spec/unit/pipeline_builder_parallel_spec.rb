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

# parallel: N and parallel:matrix through PipelineBuilder (TASK-18).
# Expected names, ordering, variables and errors are upstream's:
# gitlab/spec/lib/gitlab/ci/config/normalizer_spec.rb,
# gitlab/spec/lib/gitlab/ci/config/entry/product/*_spec.rb,
# gitlab/lib/gitlab/ci/variables/builder.rb (CI_NODE_*).
RSpec.describe PipelineBuilder do
  around do |example|
    Dir.mktmpdir('pipeline_parallel') do |dir|
      @dir = dir
      example.run
    end
  end

  def build(yaml, variables: {})
    File.write(File.join(@dir, '.gitlab-ci.yml'), yaml)
    PipelineBuilder.build(File.join(@dir, '.gitlab-ci.yml'), PinnedPipelineContext.context(@dir, variables: variables))
  end

  def built(yaml, **opts)
    result = build(yaml, **opts)
    raise "unexpected errors: #{result.errors}" unless result.ok?

    result
  end

  def pipeline_jobs(yaml, **opts)
    built(yaml, **opts).pipeline_jobs
  end

  describe 'job names and order (Normalizer)' do
    it "expands parallel: N to 'name i/N', in place of the job" do
      jobs = pipeline_jobs(<<~YAML)
        first: {script: [echo]}
        rspec: {script: [echo], parallel: 3}
        last: {script: [echo]}
      YAML
      expect(jobs.keys).to eq(['first', 'rspec 1/3', 'rspec 2/3', 'rspec 3/3', 'last'])
    end

    it 'expands a matrix entry by entry, combinations in key order (upstream complex matrix)' do
      jobs = pipeline_jobs(<<~YAML)
        rspec:
          script: [echo]
          parallel:
            matrix:
              - PLATFORM: [centos]
                STACK: [ruby, python, java]
                DB: [postgresql, mysql]
              - PLATFORM: [ubuntu]
                PROVIDER: [aws, gcp]
      YAML
      expect(jobs.keys).to eq([
                                'rspec: [centos, ruby, postgresql]', 'rspec: [centos, ruby, mysql]',
                                'rspec: [centos, python, postgresql]', 'rspec: [centos, python, mysql]',
                                'rspec: [centos, java, postgresql]', 'rspec: [centos, java, mysql]',
                                'rspec: [ubuntu, aws]', 'rspec: [ubuntu, gcp]'
                              ])
    end

    it 'takes a scalar value as a one-value list and numbers as their text, unquoted' do
      jobs = pipeline_jobs(<<~YAML)
        t:
          script: [echo]
          parallel:
            matrix:
              - V: "3.10"
                N: [1, 10]
                S: ["a b", "${X}"]
      YAML
      expect(jobs.keys).to eq(['t: [3.10, 1, a b]', 't: [3.10, 1, ${X}]', 't: [3.10, 10, a b]', 't: [3.10, 10, ${X}]'])
    end

    it "drops a job whose matrix is empty, as upstream (no instance)" do
      expect(pipeline_jobs("a: {script: [echo]}\nb:\n  script: [echo]\n  parallel: {matrix: []}\n").keys).to eq(['a'])
    end

    it 'leaves hidden templates alone and expands the job that extends one' do
      result = built(<<~YAML)
        .tpl: {parallel: 2}
        job: {extends: .tpl, script: [echo]}
      YAML
      expect(result.job_definitions.keys).to eq(['.tpl', 'job 1/2', 'job 2/2'])
      expect(result.job_definitions['.tpl']).to eq('parallel' => 2)
    end

    it 'checks stages on the instances, naming them as upstream does' do
      expect(build("j:\n  stage: nope\n  script: [echo]\n  parallel: 2\n").errors.first)
        .to start_with('j 1/2 job: chosen stage nope does not exist')
    end
  end

  describe 'variables of an instance' do
    let(:yaml) do
      <<~YAML
        variables:
          P: root
        deploy:
          script: [echo]
          variables:
            P: job
            OWN: own
          parallel:
            matrix:
              - P: [aws, gcp]
      YAML
    end

    it "puts the matrix variables over the job's own variables:" do
      jobs = pipeline_jobs(yaml)
      expect(jobs['deploy: [aws]']['variables']).to eq('P' => 'aws', 'OWN' => 'own')
      expect(jobs['deploy: [gcp]']['variables']).to eq('P' => 'gcp', 'OWN' => 'own')
    end

    it 'sets CI_NODE_INDEX (1-based over the whole matrix) and CI_NODE_TOTAL' do
      jobs = pipeline_jobs(yaml)
      expect(described_class.job_predefined_variables('deploy: [gcp]', jobs['deploy: [gcp]']))
        .to include('CI_NODE_INDEX' => '2', 'CI_NODE_TOTAL' => '2', 'CI_JOB_GROUP_NAME' => 'deploy')
    end

    it 'sets CI_NODE_INDEX/TOTAL for parallel: N, and only CI_NODE_TOTAL=1 for any other job' do
      jobs = pipeline_jobs("t: {script: [echo], parallel: 3}\nplain: {script: [echo]}\n")
      expect(described_class.job_predefined_variables('t 3/3', jobs['t 3/3']))
        .to include('CI_NODE_INDEX' => '3', 'CI_NODE_TOTAL' => '3')
      plain = described_class.job_predefined_variables('plain', jobs['plain'])
      expect(plain).to include('CI_NODE_TOTAL' => '1')
      expect(plain).not_to have_key('CI_NODE_INDEX')
    end

    it 'evaluates rules per instance with its matrix variables (rules:variables still win)' do
      jobs = pipeline_jobs(<<~YAML)
        deploy:
          script: [echo]
          parallel:
            matrix:
              - PROVIDER: [aws, gcp]
          rules:
            - if: $PROVIDER == "aws"
              variables:
                PROVIDER: from-rule
      YAML
      expect(jobs.keys).to eq(['deploy: [aws]'])
      expect(jobs['deploy: [aws]']['variables']).to eq('PROVIDER' => 'from-rule')
    end

    it 'lets a CLI variable outrank a matrix variable in rules' do
      yaml = "d:\n  script: [echo]\n  parallel: {matrix: [{P: [aws, gcp]}]}\n  rules: [{if: $P == \"aws\"}]\n"
      expect(pipeline_jobs(yaml, variables: { 'P' => 'aws' }).keys).to eq(['d: [aws]', 'd: [gcp]'])
    end

    it "lets rules see the job's own variables:, as upstream's yaml_variables" do
      expect(pipeline_jobs("j:\n  script: [echo]\n  variables: {V: x}\n  rules: [{if: $V == \"x\"}]\n").keys).to eq(['j'])
    end
  end

  describe 'validation (Entry::Product::Parallel, Matrix, Variables)' do
    {
      'parallel: "3"' => 'jobs:j:parallel should be an integer or a hash',
      'parallel: 0' => 'jobs:j:parallel config must be greater than or equal to 1',
      'parallel: 201' => 'jobs:j:parallel config must be less than or equal to 200',
      'parallel: 1.5' => 'jobs:j:parallel config must be an integer',
      'parallel: {}' => 'jobs:j:parallel config missing required keys: matrix',
      'parallel: {matrix: [{A: [a]}], x: 1}' => 'jobs:j:parallel config contains unknown keys: x',
      'parallel: {matrix: {A: [a]}}' => 'jobs:j:parallel:matrix config should be an array of hashes',
      'parallel: {matrix: [{}]}' => 'jobs:j:parallel:matrix:variables config requires at least 1 items',
      'parallel: {matrix: [{V: [3.10]}]}' =>
        'jobs:j:parallel:matrix:variables config should be a hash of key value pairs, value can be an array',
      'parallel: {matrix: [{V: [[a]]}]}' =>
        'jobs:j:parallel:matrix:variables config should be a hash of key value pairs, value can be an array',
      'parallel: {matrix: [{V: null}]}' =>
        'jobs:j:parallel:matrix:variables config should be a hash of key value pairs, value can be an array',
      'parallel: {matrix: [{A: [1,2,3,4,5,6,7,8,9,10], B: [1,2,3,4,5,6,7,8,9,10], C: [1,2,3]}]}' =>
        'jobs:j:parallel:matrix config generates too many jobs (maximum is 200)',
    }.each do |setting, message|
      it "rejects #{setting}" do
        expect(build("x: {script: [echo]}\nj:\n  script: [echo]\n  #{setting}\n").errors).to include(message)
      end
    end

    it 'accepts exactly 200 instances' do
      yaml = "j:\n  script: [echo]\n  parallel: {matrix: [{A: [#{(1..20).to_a.join(',')}], B: [#{(1..10).to_a.join(',')}]}]}\n"
      expect(pipeline_jobs(yaml).size).to eq(200)
    end

    it 'does not validate hidden templates' do
      expect(build(".t: {parallel: 0}\nj: {script: [echo]}\n").errors).to eq([])
    end
  end
end
