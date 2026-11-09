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
      expect(dry_run_jobs.sort).to eq(expected)
      expect(export_just_jobs.sort).to eq(expected)
    end

    it 'skip the include in every command for another pipeline source' do
      expected = %w[base]
      args = ['--pipeline', 'merge_request']
      expect(lint_jobs(*args).sort).to eq(expected)
      expect(dry_run_jobs(*args).sort).to eq(expected)
      expect(export_just_jobs(*args).sort).to eq(expected)
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
