# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'spec_helper'
require 'open3'
require 'tmpdir'

# `run` executes a job like a GitLab Runner shell executor (TASK-22).
# Scripts here only echo, test, cd, exit and sleep: run executes on the host.
RSpec.describe 'run', type: :integration do
  let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }

  around do |example|
    Dir.mktmpdir('run_spec') do |dir|
      @project_dir = File.realpath(dir)
      example.run
    end
  end

  def write_config(yaml)
    File.write(File.join(@project_dir, '.gitlab-ci.yml'), yaml)
  end

  # From `/`, so the job's cwd cannot be the caller's by accident.
  def run_job(job, *args)
    stdout, stderr, status = Open3.capture3(bin_path, 'run', job, *PinnedPipelineContext::CLI_ARGS, *args,
                                            '--entry', File.join(@project_dir, '.gitlab-ci.yml'), chdir: '/')
    [stdout, stderr, status.exitstatus]
  end

  describe 'variables' do
    before do
      write_config(<<~YAML)
        variables:
          GLOBAL: global
          FROM_GLOBAL: "g-$GLOBAL"
        job:
          variables:
            JOBVAR: job
          rules:
            - variables:
                RULEVAR: rule
          script:
            - echo "GLOBAL=[$GLOBAL] FROM_GLOBAL=[$FROM_GLOBAL] JOBVAR=[$JOBVAR] RULEVAR=[$RULEVAR] CLIVAR=[$CLIVAR]"
            - echo "CI=[$CI] NAME=[$CI_JOB_NAME] STATUS=[$CI_JOB_STATUS] BRANCH=[$CI_COMMIT_BRANCH] TAG=[${CI_COMMIT_TAG-unset}]"
            - echo 'quoted [$CLIVAR]'
            - printenv CLIVAR
      YAML
    end

    it 'exports predefined, global, job, rules and CLI variables to the shell' do
      stdout, stderr, status = run_job('job', '--variables', 'CLIVAR=cli')
      expect(status).to eq(0), stderr
      expect(stdout).to include('GLOBAL=[global] FROM_GLOBAL=[g-global] JOBVAR=[job] RULEVAR=[rule] CLIVAR=[cli]')
      expect(stdout).to include('CI=[true] NAME=[job] STATUS=[running] BRANCH=[main] TAG=[unset]')
    end

    it 'does not paste CLI values into the script text (single quotes stay literal)' do
      stdout, stderr, status = run_job('job', '--variables', 'CLIVAR=cli')
      expect(status).to eq(0), stderr
      expect(stdout).to include('quoted [$CLIVAR]')
      expect(stdout).to match(/^cli$/) # printenv: really in the environment
    end
  end

  describe 'script phases' do
    it 'runs before_script and script in one shell, in the project directory' do
      write_config(<<~YAML)
        job:
          before_script:
            - echo "start=$(pwd)"
            - export CARRIED=yes
            - cd /
          script:
            - echo "carried=[$CARRIED] now=$(pwd)"
      YAML
      stdout, stderr, status = run_job('job')
      expect(status).to eq(0), stderr
      expect(stdout).to include("start=#{@project_dir}", 'carried=[yes] now=/')
    end

    it 'keeps a multi-line entry one command' do
      write_config(<<~YAML)
        job:
          script:
            - |
              if true; then
                echo inside-block
              fi
      YAML
      stdout, stderr, status = run_job('job')
      expect(status).to eq(0), stderr
      expect(stdout).to include('inside-block')
    end

    it 'stops at a failing pipeline element (pipefail) and errexit' do
      write_config(<<~YAML)
        job:
          script:
            - false | true
            - echo not-reached
      YAML
      stdout, _stderr, status = run_job('job')
      expect(status).to eq(1)
      expect(stdout).not_to include('not-reached')
    end

    it "propagates the job's exit code" do
      write_config("job:\n  script: [exit 7]\n")
      _stdout, stderr, status = run_job('job')
      expect(status).to eq(7)
      expect(stderr).to include("Job 'job' failed with exit code 7")
    end

    it 'runs after_script in a separate shell, after a failure, with CI_JOB_STATUS=failed' do
      write_config(<<~YAML)
        job:
          script:
            - export IN_SCRIPT=leaked
            - cd /
            - exit 3
          after_script:
            - echo "after status=[$CI_JOB_STATUS] in_script=[$IN_SCRIPT] pwd=$(pwd)"
      YAML
      stdout, _stderr, status = run_job('job')
      expect(status).to eq(3)
      expect(stdout).to include("after status=[failed] in_script=[] pwd=#{@project_dir}")
    end

    it 'gives after_script CI_JOB_STATUS=success and ignores its failure' do
      write_config(<<~YAML)
        job:
          script: [echo ok]
          after_script:
            - echo "after status=[$CI_JOB_STATUS]"
            - exit 9
      YAML
      stdout, stderr, status = run_job('job')
      expect(status).to eq(0)
      expect(stdout).to include('after status=[success]')
      expect(stderr).to include('after_script failed with exit code 9; the job result is unchanged')
    end

    it 'kills after_script at RUNNER_AFTER_SCRIPT_TIMEOUT without changing the result' do
      write_config(<<~YAML)
        job:
          variables:
            RUNNER_AFTER_SCRIPT_TIMEOUT: 1s
          script: [echo ok]
          after_script:
            - sleep 30
            - echo not-reached
      YAML
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = run_job('job')
      elapsed_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect(status).to eq(0)
      expect(stdout).not_to include('not-reached')
      expect(stderr).to include('after_script timed out after 1.0s')
      expect(elapsed_s).to be < 20
    end
  end

  describe 'allow_failure' do
    it 'reports an allowed failure and exits 0' do
      write_config("job:\n  allow_failure: true\n  script: [exit 4]\n")
      stdout, _stderr, status = run_job('job')
      expect(status).to eq(0)
      expect(stdout).to include('job: failed (exit code 4, allowed to fail)')
    end

    it 'allows only the listed exit_codes' do
      write_config(<<~YAML)
        listed: {allow_failure: {exit_codes: [4, 5]}, script: [exit 5]}
        unlisted: {allow_failure: {exit_codes: 4}, script: [exit 6]}
      YAML
      expect(run_job('listed').last).to eq(0)
      stdout, _stderr, status = run_job('unlisted')
      expect(status).to eq(6)
      expect(stdout).to include('unlisted: failed (exit code 6)')
    end
  end

  describe '--run-deps incl' do
    before do
      write_config(<<~YAML)
        stages: [build, test, deploy]
        build: {stage: build, script: [echo RAN-build]}
        lint: {stage: build, script: [echo RAN-lint]}
        unit: {stage: test, needs: [], script: [echo RAN-unit]}
        integration: {stage: test, needs: [build], script: [echo RAN-integration]}
        deploy: {stage: deploy, script: [echo RAN-deploy]}
        broken: {stage: build, script: [echo RAN-broken; exit 2]}
        rescue: {stage: test, when: on_failure, script: [echo RAN-rescue]}
        notify: {stage: test, when: always, script: [echo RAN-notify]}
        after_broken: {stage: deploy, needs: [broken], script: [echo RAN-after_broken]}
      YAML
    end

    def ran(stdout)
      stdout.scan(/^RAN-(\S+)$/).flatten
    end

    it 'runs nothing before a needs: [] job' do
      stdout, stderr, status = run_job('unit', '--run-deps', 'incl')
      expect(status).to eq(0), stderr
      expect(ran(stdout)).to eq(%w[unit])
    end

    it 'runs only the needs of a DAG job' do
      stdout, _stderr, status = run_job('integration', '--run-deps', 'incl')
      expect(status).to eq(0)
      expect(ran(stdout)).to eq(%w[build integration])
    end

    it 'runs every earlier-stage job before a stage job, with when: deciding on the outcome' do
      stdout, _stderr, status = run_job('deploy', '--run-deps', 'incl')
      expect(status).to eq(2) # broken's exit code
      expect(ran(stdout)).to eq(%w[build lint broken unit integration rescue notify])
      expect(stdout).to include("Job 'deploy' skipped", 'deploy: skipped', 'broken: failed (exit code 2)')
    end

    it 'skips when: on_failure jobs when everything before them succeeded' do
      write_config(<<~YAML)
        build: {stage: build, script: [echo RAN-build]}
        rescue: {stage: test, when: on_failure, script: [echo RAN-rescue]}
        deploy: {stage: deploy, script: [echo RAN-deploy]}
      YAML
      stdout, _stderr, status = run_job('deploy', '--run-deps', 'incl')
      expect(status).to eq(0)
      expect(ran(stdout)).to eq(%w[build deploy])
      expect(stdout).to include('rescue: skipped')
    end

    it 'runs the job alone without --run-deps, whatever its needs and when:' do
      stdout, _stderr, status = run_job('rescue')
      expect(status).to eq(0)
      expect(ran(stdout)).to eq(%w[rescue])
    end
  end

  it 'refuses a trigger job as the target' do
    write_config("child:\n  trigger: {include: child.yml}\n")
    _stdout, stderr, status = run_job('child')
    expect(status).to eq(1)
    expect(stderr).to include("Job 'child' has no script (a trigger job): nothing to run locally")
  end
end
