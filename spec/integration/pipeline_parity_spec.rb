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
require 'json'
require 'tmpdir'

# Every subcommand must see the jobs PipelineBuilder produces (TASK-4).
# Black-box: drives bin/gitlab_ci_cli and reads the job set back out of each
# command's output, so it cannot pass by testing a shared helper alone.
RSpec.describe 'Pipeline parity across subcommands', type: :integration do
  let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }
  let(:runners_dir) { File.expand_path('../../runners', __dir__) }

  around do |example|
    Dir.mktmpdir('pipeline_parity') do |dir|
      @project_dir = dir
      example.run
    end
  end

  def write(name, content)
    File.write(File.join(@project_dir, name), content)
  end

  def entry
    File.join(@project_dir, '.gitlab-ci.yml')
  end

  def cli(*args)
    stdout, stderr, status = Open3.capture3(bin_path, *args, '--entry', entry)
    [stdout, stderr, status.exitstatus]
  end

  # Job names per command, read from the command's own output.

  def lint_jobs(*args)
    stdout, stderr, = cli('lint', '--format', 'json', *args)
    JSON.parse(stdout).fetch('jobs')
  rescue JSON::ParserError
    raise "lint did not print JSON: #{stdout}#{stderr}"
  end

  def dag_jobs(*args)
    stdout, stderr, status = cli('dag', *args)
    raise "dag failed (#{status}): #{stderr}" unless status.zero?

    stdout.scan(/^\s+\w+ \[label="([^"]+)", tooltip=/).flatten
  end

  def dry_run_jobs(*args)
    stdout, stderr, status = cli('dry-run', '--runners', runners_dir, *args)
    raise "dry-run failed (#{status}): #{stdout}#{stderr}" unless status.zero?

    stdout.scan(/Job '([^']+)' → Runner/).flatten.uniq
  end

  def export_just_jobs(*args)
    stdout, stderr, status = cli('export-just', '--flat', *args)
    raise "export-just failed (#{status}): #{stderr}" unless status.zero?

    stdout.scan(/^([A-Za-z0-9_-]+):$/).flatten
  end

  context 'include: rules' do
    before do
      write('inc.yml', <<~YAML)
        incjob:
          stage: build
          script: [echo inc]
      YAML
      write('.gitlab-ci.yml', <<~YAML)
        include:
          - local: inc.yml
            rules:
              - if: $CI_PIPELINE_SOURCE == "push"
        stages: [build]
        base:
          stage: build
          script: [echo base]
      YAML
    end

    it 'see predefined CI_PIPELINE_SOURCE in every command (push pipeline includes the file)' do
      expected = %w[base incjob]
      expect(lint_jobs.sort).to eq(expected)
      expect(dag_jobs.sort).to eq(expected)
      expect(dry_run_jobs.sort).to eq(expected)
      expect(export_just_jobs.sort).to eq(expected)
    end

    it 'skip the include in every command for another pipeline source' do
      expected = %w[base]
      args = ['--pipeline', 'merge_request']
      expect(lint_jobs(*args).sort).to eq(expected)
      expect(dag_jobs(*args).sort).to eq(expected)
      expect(dry_run_jobs(*args).sort).to eq(expected)
      expect(export_just_jobs(*args).sort).to eq(expected)
    end
  end

  context 'dag' do
    it 'resolves extends: stage and needs inherited from a template shape the graph' do
      write('.gitlab-ci.yml', <<~YAML)
        stages: [build, test, deploy]
        .t:
          stage: deploy
          needs: [a]
        a:
          stage: build
          script: [echo]
        x:
          stage: build
          script: [echo]
        job:
          extends: .t
          script: [echo]
      YAML
      dot, = cli('dag')
      deploy_cluster = dot[/subgraph cluster_deploy \{.*?\n  \}/m]
      expect(deploy_cluster).to include('label="job"')
      expect(dot).to match(/^\s+a -> job/)
    end

    it 'draws neither hidden templates nor top-level globals as jobs' do
      write('.gitlab-ci.yml', <<~YAML)
        image: {name: alpine}
        services: [{name: postgres}]
        cache: {paths: [vendor]}
        default: {tags: [x]}
        .tmpl:
          script: [echo]
          stage: test
        job:
          extends: .tmpl
      YAML
      expect(dag_jobs).to eq(%w[job])
    end
  end

  context 'rules' do
    before do
      write('.gitlab-ci.yml', <<~YAML)
        image: {name: alpine}
        cache: {paths: [vendor]}
        stages: [build, test]
        .tpl:
          stage: build
          script: [echo tpl]
        compile:
          extends: .tpl
        never_job:
          stage: test
          script: [echo SHOULD-NOT-RUN]
          rules:
            - when: never
        mr_only:
          stage: test
          script: [echo mr]
          rules:
            - if: $CI_PIPELINE_SOURCE == "merge_request"
        needs_mr_only:
          stage: test
          script: [echo cascade]
          needs: [mr_only]
        unit:
          stage: test
          script: [echo unit]
          needs: [compile]
      YAML
    end

    it 'give dag, dry-run and export-just the identical job set' do
      expected = %w[compile unit]
      expect(dag_jobs.sort).to eq(expected)
      expect(dry_run_jobs.sort).to eq(expected)
      expect(export_just_jobs.sort).to eq(expected)
    end

    it 'follow the pipeline context the same way in every command' do
      expected = %w[compile mr_only needs_mr_only unit]
      args = ['--pipeline', 'merge_request']
      expect(dag_jobs(*args).sort).to eq(expected)
      expect(dry_run_jobs(*args).sort).to eq(expected)
      expect(export_just_jobs(*args).sort).to eq(expected)
    end

    it 'make run refuse a rule-excluded job, saying why, without executing it' do
      stdout, stderr, status = cli('run', 'never_job')
      expect(status).to eq(1)
      expect(stdout).not_to include('SHOULD-NOT-RUN')
      expect(stderr).to include("Job 'never_job' is excluded by rules in this pipeline context: matching rule has when: never")

      _stdout, stderr, = cli('run', 'needs_mr_only')
      expect(stderr).to include("needs 'mr_only', which is not in this pipeline")
    end

    it 'make run refuse a hidden template' do
      _stdout, stderr, status = cli('run', '.tpl')
      expect(status).to eq(1)
      expect(stderr).to include("Job '.tpl' is a hidden template")
    end

    it 'leave lint validating every job regardless of rules' do
      expect(lint_jobs).to include('never_job', 'mr_only', '.tpl')
    end
  end

  context 'workflow:rules matching nothing' do
    before do
      write('.gitlab-ci.yml', <<~YAML)
        workflow:
          rules:
            - if: $NOPE == "1"
        job:
          script: [echo]
      YAML
    end

    it 'create no pipeline in any command' do
      [['dag'], ['dry-run', '--runners', runners_dir], ['export-just'], %w[run job]].each do |command, *extra|
        stdout, stderr, status = cli(command, *extra)
        expect(status).not_to eq(0), "#{command} exited 0"
        expect(stdout + stderr).to include('workflow:rules: matched no rule'), command
      end
    end
  end

  context '--project' do
    it 'is where include:local resolves from' do
      Dir.mktmpdir('pipeline_parity_root') do |root|
        File.write(File.join(root, 'inc.yml'), "rootjob:\n  script: [echo]\n")
        write('.gitlab-ci.yml', "include:\n  - local: inc.yml\nbase:\n  script: [echo]\n")

        expect(lint_jobs('--project', root).sort).to eq(%w[base rootjob])
      end
    end
  end

  context 'errors' do
    it 'are printed once by commands that build the pipeline' do
      write('.gitlab-ci.yml', "a:\n  extends: .missing\n  script: [echo]\n")
      [['dry-run', '--runners', runners_dir], ['export-just'], %w[run a]].each do |command, *extra|
        _stdout, stderr, status = cli(command, *extra)
        expect(status).not_to eq(0)
        expect(stderr.lines.grep(/\.missing/).size).to eq(1), "#{command} stderr: #{stderr}"
      end
    end
  end
end
