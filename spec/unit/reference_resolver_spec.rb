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
require 'open3'
require 'pipeline_builder'

# !reference through the whole PipelineBuilder (load, includes, extends,
# references, list flattening, rules), as every subcommand sees it.
# Reference: gitlab/lib/gitlab/ci/config/yaml/tags/{reference,resolver,base}.rb
# and doc/ci/yaml/yaml_optimization.md "!reference tags".
RSpec.describe ReferenceResolver do
  around do |example|
    Dir.mktmpdir('reference_resolver') do |dir|
      @dir = dir
      example.run
    end
  end

  def write(name, content)
    File.write(File.join(@dir, name), content)
  end

  def context
    PipelineBuilder::Context.new(project_dir: @dir, gitlab_dir: nil,
                                 pipeline_source: PinnedPipelineContext::PIPELINE_SOURCE,
                                 variables: PinnedPipelineContext::VARIABLES.dup)
  end

  def build(yaml)
    write('.gitlab-ci.yml', yaml)
    PipelineBuilder.build(File.join(@dir, '.gitlab-ci.yml'), context)
  end

  def config(yaml)
    result = build(yaml)
    raise "unexpected errors: #{result.errors}" unless result.ok?

    result.config
  end

  def errors(yaml)
    build(yaml).errors
  end

  it 'splices a referenced script into a script list (audit_config/13 repro)' do
    expect(config(<<~YAML)['job']['script']).to eq(['echo setup', 'echo main'])
      .setup:
        script: [echo setup]
      job:
        script:
          - !reference [.setup, script]
          - echo main
    YAML
  end

  it 'resolves a reference into an included file' do
    write('lib.yml', ".setup:\n  script: [echo setup]\n")
    expect(config(<<~YAML)['job']['script']).to eq(['echo setup', 'echo main'])
      include: [{local: lib.yml}]
      job:
        script:
          - !reference [.setup, script]
          - echo main
    YAML
  end

  it 'resolves a reference written in an included file' do
    write('lib.yml', "job:\n  script:\n    - !reference [.setup, script]\n    - echo inc\n")
    expect(config(<<~YAML)['job']['script']).to eq(['echo setup', 'echo inc'])
      include: [{local: lib.yml}]
      .setup:
        script: [echo setup]
    YAML
  end

  it 'resolves nested references (yaml_optimization.md example)' do
    expect(config(<<~YAML)['nested-references']['script']).to eq(['echo "ONE!"', 'echo "TWO!"', 'echo "THREE!"'])
      .snippets:
        one:
          - echo "ONE!"
        two:
          - !reference [.snippets, one]
          - echo "TWO!"
        three:
          - !reference [.snippets, two]
          - echo "THREE!"
      nested-references:
        script:
          - !reference [.snippets, three]
    YAML
  end

  it 'resolves a whole variables map and a single variable' do
    result = config(<<~YAML)
      .vars:
        variables:
          URL: "http://my-url.internal"
          IMPORTANT_VAR: "the details"
      job-all:
        variables: !reference [.vars, variables]
        script: [echo]
      job-one:
        variables:
          MY_VAR: !reference [.vars, variables, IMPORTANT_VAR]
        script: [echo]
    YAML
    expect(result['job-all']['variables']).to eq('URL' => 'http://my-url.internal', 'IMPORTANT_VAR' => 'the details')
    expect(result['job-one']['variables']).to eq('MY_VAR' => 'the details')
  end

  it 'resolves a reference to a global key' do
    expect(config(<<~YAML)['job']['before_script']).to eq(['echo global', 'echo job'])
      before_script: [echo global]
      job:
        before_script:
          - !reference [before_script]
          - echo job
        script: [echo]
    YAML
  end

  # Cross-task (TASK-31): upstream resolves tags after Extendable, which
  # extends hidden templates too.
  it 'sees the extended result of a template' do
    result = config(<<~YAML)
      .base:
        script: [base]
        variables: {A: a}
      .tpl:
        extends: .base
        variables: {B: b}
      job:
        variables: !reference [.tpl, variables]
        script: !reference [.tpl, script]
      own:
        script: [own]
      job2:
        script:
          - !reference [.tpl, script]
          - !reference [own, script]
    YAML
    expect(result['job']).to eq('variables' => { 'A' => 'a', 'B' => 'b' }, 'script' => ['base'])
    expect(result['job2']['script']).to eq(%w[base own])
  end

  describe 'rules' do
    # audit_rules/p1/n1.yml: a nested `when: never` must win, not be skipped.
    it 'flattens rules nested by !reference and by a YAML alias' do
      result = build(<<~YAML)
        .never_rules: &never_rules
          - if: '$CI_COMMIT_BRANCH'
            when: never
        .ref_rules:
          rules:
            - if: '$CI_COMMIT_BRANCH'
              when: never
        anchor_nested:
          script: echo
          rules:
            - *never_rules
            - when: on_success
        ref_nested:
          script: echo
          rules:
            - !reference [.ref_rules, rules]
            - when: on_success
        plain:
          script: echo
      YAML

      expect(result.errors).to eq([])
      expect(result.pipeline_jobs.keys).to eq(['plain'])
      expect(result.excluded_jobs).to eq('anchor_nested' => 'matching rule has when: never',
                                         'ref_nested' => 'matching rule has when: never')
      expect(result.config['ref_nested']['rules']).to eq([{ 'if' => '$CI_COMMIT_BRANCH', 'when' => 'never' },
                                                          { 'when' => 'on_success' }])
    end

    # Upstream Include::Rules is a ComposableArray too; tags are not
    # resolved before includes, so only a YAML alias can nest here.
    it 'flattens include:rules nested by a YAML alias' do
      write('inc.yml', "incjob: {script: [echo]}\n")
      result = build(<<~YAML)
        .never: &never
          - if: '$CI_COMMIT_BRANCH'
            when: never
        include:
          - local: inc.yml
            rules:
              - *never
              - when: always
        job: {script: [echo]}
      YAML
      expect(result.errors).to eq([])
      expect(result.pipeline_jobs.keys).to eq(['job'])
    end

    it 'flattens workflow:rules' do
      result = build(<<~YAML)
        .wf: {rules: [{if: '$CI_COMMIT_BRANCH', when: never}]}
        workflow:
          rules:
            - !reference [.wf, rules]
            - when: always
        job: {script: [echo]}
      YAML
      expect(result.workflow_skipped).to be true
    end
  end

  it 'flattens needs built from references' do
    expect(config(<<~YAML)['c']['needs']).to eq(%w[a b])
      .deps: {needs: [a, b]}
      a: {script: [echo]}
      b: {script: [echo]}
      c:
        script: [echo]
        needs:
          - !reference [.deps, needs]
    YAML
  end

  # The tag, not the shape, makes a reference: the same two strings
  # untagged are data.
  it 'leaves a literal two-string list untouched' do
    result = config(<<~YAML)
      .setup:
        script: [echo setup]
      job:
        script: [echo]
        artifacts:
          paths: [".setup", "script"]
        variables:
          LIST: [".setup", "script"]
    YAML
    expect(result['job']['artifacts']['paths']).to eq(['.setup', 'script'])
    expect(result['job']['variables']['LIST']).to eq(['.setup', 'script'])
  end

  describe 'errors (upstream texts)' do
    it 'reports a missing target' do
      expect(errors("job:\n  script:\n    - !reference [.nope, script]\n"))
        .to eq(['!reference [".nope", "script"] could not be found'])
    end

    it 'reports a path through a non-Hash as missing' do
      expect(errors(".a: {script: [x]}\njob:\n  script: !reference [.a, script, x]\n"))
        .to eq(['!reference [".a", "script", "x"] could not be found'])
    end

    it 'reports a cycle' do
      expect(errors(<<~YAML)).to eq(['!reference [".b", "script"] is part of a circular chain'])
        .a: {script: !reference [.b, script]}
        .b: {script: !reference [.a, script]}
        job: {script: [x]}
      YAML
    end

    it 'reports a reference to itself as a cycle' do
      expect(errors("job:\n  script: !reference [job, script]\n"))
        .to eq(['!reference ["job", "script"] is part of a circular chain'])
    end

    it 'reports a non-list reference as invalid' do
      expect(errors("job:\n  script: !reference .setup\n")).to eq(['!reference ".setup" is not valid'])
    end

    it 'reports an empty reference as invalid' do
      expect(errors("job:\n  script: !reference []\n")).to eq(['!reference [] is not valid'])
    end
  end

  it 'gives each use site its own copy' do
    result = config(<<~YAML)
      .v: {variables: {A: a}}
      x: {script: [echo], variables: !reference [.v, variables]}
      y: {script: [echo], variables: !reference [.v, variables]}
    YAML
    result['x']['variables']['A'] = 'mutated'
    expect(result['y']['variables']).to eq('A' => 'a')
  end

  it 'lets export-just print a referenced script instead of crashing' do
    write('.gitlab-ci.yml', <<~YAML)
      .setup:
        script: [echo setup]
      job:
        script:
          - !reference [.setup, script]
          - echo main
    YAML
    bin = File.expand_path('../../bin/gitlab_ci_cli', __dir__)
    stdout, stderr, status = Open3.capture3(bin, 'export-just', *PinnedPipelineContext::CLI_ARGS,
                                            '--entry', File.join(@dir, '.gitlab-ci.yml'))

    expect(stderr).not_to include('Export failed')
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include('echo setup').and include('echo main')
  end
end
