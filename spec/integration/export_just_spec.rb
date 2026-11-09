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

# export-just writes recipes that behave like `run` (TASK-51, TASK-23).
# The generated recipes are executed with `just` (from the dev shell);
# scripts here only echo, export, cd and exit.
RSpec.describe 'export-just', type: :integration do
  let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }

  around do |example|
    Dir.mktmpdir('export_just_spec') do |dir|
      @project_dir = File.realpath(dir)
      example.run
    end
  end

  def justfile_path
    File.join(@project_dir, 'justfile.gitlab')
  end

  def export(yaml, *args)
    File.write(File.join(@project_dir, '.gitlab-ci.yml'), yaml)
    _stdout, stderr, status = Open3.capture3(bin_path, 'export-just', *PinnedPipelineContext::CLI_ARGS, *args,
                                             '--entry', File.join(@project_dir, '.gitlab-ci.yml'),
                                             '--output', justfile_path)
    raise "export-just failed (#{status.exitstatus}): #{stderr}" unless status.success?

    File.read(justfile_path)
  end

  # From `/`, so the recipe's cwd cannot be the caller's by accident.
  def just(*args)
    stdout, stderr, status = Open3.capture3('just', '--justfile', justfile_path, *args, chdir: '/')
    [stdout, stderr, status.exitstatus]
  end

  it 'writes a justfile just accepts for multi-line entries, heredocs and {{' do
    export(<<~YAML)
      job:
        script:
          - |
            cat <<EOF
            <?xml version="1.0"?>
              {{ not.a.just.expression }}
            EOF
          - echo '{{x}}'
    YAML
    _stdout, stderr, status = just('--evaluate')
    expect(status).to eq(0), stderr
    stdout, stderr, status = just('job')
    expect(status).to eq(0), stderr
    expect(stdout).to eq("<?xml version=\"1.0\"?>\n  {{ not.a.just.expression }}\n{{x}}\n")
  end

  it 'runs the job like `run`: variables exported, one shell, project dir, pipefail' do
    export(<<~YAML, '--variables', "CLIVAR=it's")
      variables:
        GLOBAL: global
      job:
        variables:
          JOBVAR: "j-$GLOBAL"
        before_script:
          - echo "start=$(pwd)"
          - export CARRIED=yes
          - cd /
        script:
          - echo "GLOBAL=[$GLOBAL] JOBVAR=[$JOBVAR] CLIVAR=[$CLIVAR] NAME=[$CI_JOB_NAME] carried=[$CARRIED] now=$(pwd)"
          - echo 'quoted [$CLIVAR]'
          - false | true
          - echo not-reached
    YAML
    stdout, _stderr, status = just('job')
    expect(status).to eq(1)
    expect(stdout).to include("start=#{@project_dir}",
                              "GLOBAL=[global] JOBVAR=[j-global] CLIVAR=[it's] NAME=[job] carried=[yes] now=/",
                              'quoted [$CLIVAR]')
    expect(stdout).not_to include('not-reached')
  end

  it 'runs after_script in a second shell, also after a failure, and keeps the exit code' do
    export(<<~YAML)
      job:
        script:
          - export IN_SCRIPT=leaked
          - exit 3
        after_script:
          - echo "after status=[$CI_JOB_STATUS] in_script=[$IN_SCRIPT] pwd=$(pwd)"
          - exit 9
    YAML
    stdout, stderr, status = just('job')
    expect(status).to eq(3)
    expect(stdout).to include("after status=[failed] in_script=[] pwd=#{@project_dir}")
    expect(stderr).to include('after_script failed or timed out (exit code 9); the job result is unchanged')
  end

  it 'makes graph recipes depend on what the job waits for, as dry-run schedules it' do
    justfile = export(<<~YAML, '--graph')
      stages: [build, test, deploy]
      build: {stage: build, script: [echo build]}
      unit: {stage: test, needs: [], script: [echo unit]}
      integration: {stage: test, needs: [build], script: [echo integration]}
      rescue: {stage: test, when: on_failure, script: [echo rescue]}
      deploy: {stage: deploy, script: [echo deploy]}
    YAML
    expect(justfile).to match(/^unit:$/)
    expect(justfile).to match(/^integration: build$/)
    expect(justfile).to match(/^deploy: build unit integration$/) # rescue: not on the success path
    _stdout, stderr, status = just('--evaluate')
    expect(status).to eq(0), stderr
  end

  it 'no longer accepts --shell' do
    File.write(File.join(@project_dir, '.gitlab-ci.yml'), "job: {script: [echo]}\n")
    _stdout, stderr, status = Open3.capture3(bin_path, 'export-just', '--shell', 'sh',
                                             '--entry', File.join(@project_dir, '.gitlab-ci.yml'))
    expect(status.exitstatus).not_to eq(0)
    expect(stderr).to include('Unknown flag: --shell')
  end
end
