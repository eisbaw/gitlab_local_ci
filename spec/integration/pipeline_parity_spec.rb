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

  def cli(command, *args)
    stdout, stderr, status = Open3.capture3(bin_path, command, *PinnedPipelineContext::CLI_ARGS, *args, '--entry', entry)
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
            - if: $CI_PIPELINE_SOURCE == "merge_request_event"
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
      args = ['--pipeline', 'merge_request_event']
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

    it 'keep jobs whose only missing needs are optional or cross-project' do
      write('.gitlab-ci.yml', <<~YAML)
        stages: [build, test]
        maybe:
          stage: build
          script: [echo maybe]
          rules:
            - if: $CI_PIPELINE_SOURCE == "schedule"
        opt:
          stage: test
          script: [echo opt]
          needs:
            - job: maybe
              optional: true
        xproj:
          stage: test
          script: [echo xproj]
          needs:
            - project: group/other
              job: compile
              ref: main
      YAML
      expect(dag_jobs.sort).to eq(%w[opt xproj])
      expect(export_just_jobs.sort).to eq(%w[opt xproj])
    end

    it 'make run refuse a hidden template' do
      _stdout, stderr, status = cli('run', '.tpl')
      expect(status).to eq(1)
      expect(stderr).to include("Job '.tpl' is a hidden template")
    end

    it 'leave lint validating every visible job regardless of rules' do
      expect(lint_jobs).to include('never_job', 'mr_only')
      expect(lint_jobs).not_to include('.tpl') # Entry::Hidden is no job (TASK-73)
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

  context 'default: and legacy globals (TASK-9)' do
    before do
      write('.gitlab-ci.yml', <<~YAML)
        before_script: [echo LEGACY-BEFORE]
        default:
          tags: [no-runner-has-this-tag]
          after_script: [echo DEFAULT-AFTER]
        job:
          script: [echo JOB-SCRIPT]
        free:
          inherit: {default: [before_script, after_script]}
          script: [echo FREE-SCRIPT]
      YAML
    end

    it 'reach every command' do
      expect(lint_jobs.sort).to eq(%w[free job])

      dot, = cli('dag')
      expect(dot[/job \[label="job", tooltip="[^"]*"/]).to include('no-runner-has-this-tag')

      # Tags: the default-tagged job never gets a runner (audit_config/03),
      # the job that opts out of default tags does.
      stdout, = cli('dry-run', '--runners', runners_dir)
      expect(stdout.scan(/Job '([^']+)' → Runner/).flatten.uniq).to eq(%w[free])
      expect(stdout).to include('Pipeline status: stuck')

      just, = cli('export-just', '--flat')
      job_recipe = just[/^job:\n(?:    .*\n)+/]
      expect(job_recipe).to include('echo LEGACY-BEFORE', 'echo JOB-SCRIPT', 'echo DEFAULT-AFTER')

      run_out, run_err, status = cli('run', 'free')
      expect(status).to eq(0), run_err
      expect(run_out.index('LEGACY-BEFORE')).to be < run_out.index('FREE-SCRIPT')
      expect(run_out.index('FREE-SCRIPT')).to be < run_out.index('DEFAULT-AFTER')
    end
  end

  context 'job keywords' do
    it 'that upstream allows are accepted by lint and dry-run alike' do
      write('.gitlab-ci.yml', <<~YAML)
        job:
          script: [echo]
          when: delayed
          start_in: 1 minute
          id_tokens:
            ID_TOKEN: {aud: https://example.com}
      YAML
      stdout, = cli('lint', '--format', 'json')
      expect(JSON.parse(stdout).fetch('warnings')).to be_empty
      expect(dry_run_jobs).to eq(%w[job])
    end
  end

  context 'workflow:rules:variables' do
    it 'override top-level variables but not CLI variables' do
      write('.gitlab-ci.yml', <<~YAML)
        variables:
          MODE: normal
        workflow:
          rules:
            - variables:
                MODE: workflow
        workflow_only:
          script: [echo]
          rules:
            - if: $MODE == "workflow"
        cli_only:
          script: [echo]
          rules:
            - if: $MODE == "nightly"
      YAML
      expect(dag_jobs).to eq(%w[workflow_only])
      expect(dag_jobs('--variables', 'MODE=nightly')).to eq(%w[cli_only])
    end
  end

  context '.pre/.post edge stages (TASK-17) and the stage check (TASK-50)' do
    it 'run .pre first and .post last in every command without declaring them' do
      write('.gitlab-ci.yml', <<~YAML)
        stages: [build]
        last:
          stage: .post
          script: [echo]
        b:
          stage: build
          script: [echo]
        first:
          stage: .pre
          script: [echo]
      YAML
      expect(lint_jobs).to eq(%w[last b first])
      expect(dag_jobs).to eq(%w[first b last])
      expect(dry_run_jobs).to eq(%w[first b last])
      expect(export_just_jobs).to contain_exactly('last', 'b', 'first')
      _stdout, stderr, status = cli('run', 'first')
      expect(stderr).not_to include('stage')
      expect(status).to eq(0)
    end

    it 'reject an undeclared stage once, in upstream wording, in every command' do
      write('.gitlab-ci.yml', "stages: [build]\nj:\n  script: [echo]\n")
      message = 'j job: chosen stage test does not exist; available stages are .pre, build, .post'
      [['lint'], ['dag'], ['dry-run', '--runners', runners_dir], ['export-just'], %w[run j]].each do |command, *extra|
        stdout, stderr, status = cli(command, *extra)
        expect(status).not_to eq(0), "#{command} exited 0"
        expect((stdout + stderr).lines.grep(/#{Regexp.escape(message)}/).size).to eq(1), "#{command}: #{stdout}#{stderr}"
      end
    end

    it 'create no pipeline from .pre/.post jobs alone' do
      write('.gitlab-ci.yml', <<~YAML)
        first:
          stage: .pre
          script: [echo]
        b:
          stage: build
          rules:
            - if: $NOPE == "1"
          script: [echo]
      YAML
      expect(dag_jobs).to eq([])
      expect(export_just_jobs).to eq([])
      _stdout, stderr, status = cli('run', 'first')
      expect(status).not_to eq(0)
      expect(stderr).to include("Job 'first' is excluded by rules in this pipeline context: only .pre/.post jobs left")
    end
  end

  # TASK-10: the standard MR rules evaluate like GitLab per pipeline type.
  # Variables that do not apply are unset (CI_COMMIT_TAG == null in a branch
  # pipeline, no CI_COMMIT_BRANCH in an MR pipeline).
  context 'predefined variables by pipeline type (TASK-10)' do
    before do
      write('.gitlab-ci.yml', <<~YAML)
        mr_event:
          script: [echo]
          rules: [{ if: '$CI_PIPELINE_SOURCE == "merge_request_event"' }]
        mr_iid:
          script: [echo]
          rules: [{ if: '$CI_MERGE_REQUEST_IID' }]
        branch_with_open_mr:
          script: [echo]
          rules: [{ if: '$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS' }]
        branch:
          script: [echo]
          rules: [{ if: '$CI_COMMIT_BRANCH == "feature-x"' }]
        tag:
          script: [echo]
          rules: [{ if: '$CI_COMMIT_TAG' }]
        not_tag:
          script: [echo]
          rules: [{ if: '$CI_COMMIT_TAG == null' }]
        ci:
          script: [echo]
          rules: [{ if: '$CI == "true" && $GITLAB_CI == "true" && $CI_JOB_NAME_SLUG == "ci"' }]
      YAML
    end

    {
      'branch pipeline' => [%w[--ref feature-x], %w[branch ci not_tag]],
      'tag pipeline' => [%w[--ref refs/tags/v1], %w[ci tag]],
      'MR pipeline' => [%w[--pipeline merge_request_event --ref feature-x], %w[ci mr_event mr_iid not_tag]],
      'MR pipeline via the merge_request alias' => [%w[--pipeline merge_request --ref feature-x],
                                                    %w[ci mr_event mr_iid not_tag]],
      'branch pipeline with an open MR' => [%w[--ref feature-x --variables CI_OPEN_MERGE_REQUESTS=g/p!1],
                                            %w[branch branch_with_open_mr ci not_tag]]
    }.each do |name, (args, expected)|
      it "selects the same jobs in every command: #{name}" do
        expect(dag_jobs(*args).sort).to eq(expected)
        expect(dry_run_jobs(*args).sort).to eq(expected)
        expect(export_just_jobs(*args).sort).to eq(expected)
      end
    end

    it 'runs the standard MR workflow: MR pipelines and branch pipelines, no tag pipeline' do
      write('.gitlab-ci.yml', <<~YAML)
        workflow:
          rules:
            - if: $CI_PIPELINE_SOURCE == "merge_request_event"
            - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS
              when: never
            - if: $CI_COMMIT_BRANCH
        job:
          script: [echo]
      YAML
      expect(dag_jobs('--pipeline', 'merge_request_event', '--ref', 'feature-x')).to eq(%w[job])
      expect(dag_jobs('--ref', 'feature-x')).to eq(%w[job])
      [%w[--ref refs/tags/v1], %w[--ref feature-x --variables CI_OPEN_MERGE_REQUESTS=g/p!1]].each do |args|
        _stdout, stderr, status = cli('dag', *args)
        expect(status).not_to eq(0)
        expect(stderr).to include('workflow:rules: matched no rule'), args.join(' ')
      end
    end

    it 'reject an MR pipeline for a tag in every command' do
      [['lint'], ['dag'], ['dry-run', '--runners', runners_dir], ['export-just'], %w[run ci]].each do |command, *extra|
        stdout, stderr, status = cli(command, *extra, '--pipeline', 'merge_request_event', '--ref', 'refs/tags/v1')
        expect(status).not_to eq(0), "#{command} exited 0"
        expect(stdout + stderr).to include('--ref v1 is a tag'), command
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

    # TASK-38: unquoted `- echo "a: b"` is a YAML mapping. Every command
    # rejects it with upstream's Entry::Commands text instead of calling it
    # valid (lint) or crashing on Hash#gsub (export-just).
    it 'reject a script entry that is not a string, with upstream wording' do
      write('.gitlab-ci.yml', "build:\n  script:\n    - echo \"Coverage: 85%\"\n")
      message = 'jobs:build:script config should be a string or a nested array of strings up to 10 levels deep'
      [['lint'], ['dag'], ['dry-run', '--runners', runners_dir], ['export-just'], %w[run build]].each do |command, *extra|
        stdout, stderr, status = cli(command, *extra)
        expect(status).not_to eq(0), "#{command} exited 0"
        expect((stdout + stderr).lines.grep(/#{Regexp.escape(message)}/).size).to eq(1), "#{command}: #{stdout}#{stderr}"
        expect(stderr).not_to match(/undefined method|NoMethodError/)
      end
    end
  end
end
