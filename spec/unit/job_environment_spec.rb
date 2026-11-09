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
require 'job_environment'

# The job environment run and export-just share (TASK-22, TASK-51).
RSpec.describe JobEnvironment do
  def variable(key, value, raw: false)
    described_class::Variable.new(key: key, value: value, raw: raw)
  end

  describe '.os_expand (runner JobVariables.Expand, Go os.Expand)' do
    lookup = { 'A' => 'a', 'B' => '$A', 'EMPTY' => '', 'X_1' => 'x1' }

    # Expected values printed by Go 1.26 os.Expand with the runner's lookup
    # (common/variables.go JobVariables.value). The port was also diffed
    # against Go on 5000 random strings over the same alphabet: identical.
    {
      '' => '', '$' => '$', '$$' => '$', '$A' => 'a', '${A}' => 'a', '${}' => '', '${' => '',
      '${A' => 'A', '$A$B' => 'a$A', 'x$' => 'x$', '$-' => '', '${-}' => '', '${1}' => '',
      '$1x' => 'x', '${A:-d}' => '', '$ A' => '$ A', '%A%' => '%A%', 'a$$b' => 'a$b',
      '${*}' => '', '$_' => '', '${{A}}' => '}', '$X_1' => 'x1', '$NOPE-y' => '-y'
    }.each do |input, expected|
      it "expands #{input.inspect} to #{expected.inspect} like Go" do
        expect(described_class.os_expand(input) { |key| described_class.runner_value(lookup, key) }).to eq(expected)
      end
    end
  end

  describe '.server_expand (GitLab sort_and_expand_all, keep_undefined)' do
    def expand(*variables)
      expanded, warnings = described_class.server_expand(variables)
      [expanded.to_h { |v| [v.key, v.value] }, warnings]
    end

    it 'expands a reference to a variable defined later in the list (topological order)' do
      expect(expand(variable('A', 'a-$B'), variable('B', 'b-${C}'), variable('C', 'c')).first)
        .to eq('A' => 'a-b-c', 'B' => 'b-c', 'C' => 'c')
    end

    it 'keeps unknown references, $$ and %% as written' do
      expect(expand(variable('A', '$NOPE ${NOPE} $$X %%')).first).to eq('A' => '$NOPE ${NOPE} $$X %%')
    end

    it 'expands the Windows %KEY% form too' do
      expect(expand(variable('B', 'b'), variable('A', '%B%')).first).to eq('B' => 'b', 'A' => 'b')
    end

    it 'leaves raw values and references to raw variables for the runner' do
      expect(expand(variable('R', 'raw-$X', raw: true), variable('X', 'x'), variable('A', '$R')).first)
        .to eq('R' => 'raw-$X', 'X' => 'x', 'A' => '$R')
    end

    it 'lets a variable extend an earlier one of the same name' do
      expanded, = described_class.server_expand([variable('P', 'base'), variable('P', '$P-ext')])
      expect(expanded.map(&:value)).to eq(%w[base base-ext])
    end

    # Text checked against upstream Collection#sort_and_expand_all loaded standalone.
    it 'reports a cycle and passes every value unexpanded, as upstream' do
      values, warnings = expand(variable('A', '$B'), variable('B', '$A'), variable('C', 'c-$D'), variable('D', 'd'))
      expect(values).to eq('A' => '$B', 'B' => '$A', 'C' => 'c-$D', 'D' => 'd')
      expect(warnings).to eq(['circular variable reference detected: ["A", "B"]; ' \
                              'variables are passed unexpanded, as upstream does'])
    end

    it 'does not take a self-reference for a cycle' do
      expect(expand(variable('A', 'x$A')).last).to eq([])
    end
  end

  describe '.go_duration_s / .after_script_timeout_s (RUNNER_AFTER_SCRIPT_TIMEOUT)' do
    { '1m30s' => 90, '1.5h' => 5400, '300ms' => 0.3, '2s' => 2, '.5s' => 0.5, '0' => 0, '-1s' => -1 }.each do |text, seconds|
      it("parses #{text}") { expect(described_class.go_duration_s(text)).to be_within(1e-9).of(seconds) }
    end

    %w[1 5 s 1x 1m-2s].each do |text|
      it("rejects #{text.inspect} like time.ParseDuration") { expect(described_class.go_duration_s(text)).to be_nil }
    end

    it 'keeps the runner default for blank, malformed, negative and zero' do
      expect(described_class.after_script_timeout_s(nil)).to eq([300, nil])
      expect(described_class.after_script_timeout_s(' ')).to eq([300, nil])
      expect(described_class.after_script_timeout_s('0s')).to eq([300, nil])
      expect(described_class.after_script_timeout_s('soon'))
        .to eq([300, 'Ignoring malformed RUNNER_AFTER_SCRIPT_TIMEOUT timeout: soon'])
      expect(described_class.after_script_timeout_s('-5s'))
        .to eq([300, 'Ignoring relative RUNNER_AFTER_SCRIPT_TIMEOUT timeout: -5s'])
      expect(described_class.after_script_timeout_s('2m')).to eq([120, nil])
    end
  end

  describe '.build' do
    around do |example|
      Dir.mktmpdir('job_environment') do |dir|
        @dir = dir
        example.run
      end
    end

    def job(yaml, name, cli: {})
      File.write(File.join(@dir, '.gitlab-ci.yml'), yaml)
      context = PinnedPipelineContext.context(@dir, variables: cli)
      result = PipelineBuilder.build(File.join(@dir, '.gitlab-ci.yml'), context)
      raise result.errors.join("\n") unless result.ok?

      described_class.build(result, name, cli_variables: context.variables, project_dir: @dir)
    end

    let(:precedence_yaml) do
      <<~YAML
        variables:
          ONLY_GLOBAL: global
          G_VS_WORKFLOW: global
          G_VS_JOB: global
          CI_COMMIT_REF_NAME: from-yaml
        workflow:
          rules:
            - variables:
                G_VS_WORKFLOW: workflow
                W_VS_JOB: workflow
        job:
          variables:
            G_VS_JOB: job
            W_VS_JOB: job
            J_VS_RULE: job
            J_VS_CLI: job
          rules:
            - variables:
                J_VS_RULE: rule
          script: [echo]
      YAML
    end

    it 'applies upstream precedence: predefined < global < workflow < job < rules:variables < CLI' do
      variables = job(precedence_yaml, 'job', cli: { 'J_VS_CLI' => 'cli' }).variables
      expect(variables.slice('ONLY_GLOBAL', 'G_VS_WORKFLOW', 'G_VS_JOB', 'W_VS_JOB', 'J_VS_RULE', 'J_VS_CLI',
                             'CI_COMMIT_REF_NAME'))
        .to eq('ONLY_GLOBAL' => 'global', 'G_VS_WORKFLOW' => 'workflow', 'G_VS_JOB' => 'job',
               'W_VS_JOB' => 'job', 'J_VS_RULE' => 'rule', 'J_VS_CLI' => 'cli', 'CI_COMMIT_REF_NAME' => 'from-yaml')
    end

    it 'exports the predefined and runner variables, and leaves unset ones unset' do
      variables = job("job:\n  stage: build\n  script: [echo]\n", 'job').variables
      expect(variables).to include('CI' => 'true', 'GITLAB_CI' => 'true', 'CI_JOB_NAME' => 'job',
                                   'CI_JOB_STAGE' => 'build', 'CI_COMMIT_BRANCH' => 'main',
                                   'CI_PROJECT_DIR' => @dir, 'CI_SERVER' => 'yes', 'CI_JOB_STATUS' => 'running')
      expect(variables).not_to have_key('CI_COMMIT_TAG')
    end

    it 'gives a job only the root variables inherit:variables lets through' do
      yaml = <<~YAML
        variables: {A: a, B: b}
        none: {inherit: {variables: false}, script: [echo]}
        some: {inherit: {variables: [B]}, script: [echo]}
      YAML
      expect(job(yaml, 'none').variables.keys).not_to include('A', 'B')
      expect(job(yaml, 'some').variables).to include('B' => 'b')
      expect(job(yaml, 'some').variables).not_to have_key('A')
    end

    it 'expands values through both steps and keeps expand: false raw' do
      yaml = <<~YAML
        variables:
          BASE: base
          RAW: {value: "raw-$BASE", expand: false}
        job:
          variables:
            REF: "$BASE/$CI_JOB_NAME"
            VIA_RAW: "$RAW"
            UNKNOWN: "[$NOT_DEFINED]"
            DOLLARS: "a$$b"
          script: [echo]
      YAML
      expect(job(yaml, 'job').variables).to include('REF' => 'base/job', 'RAW' => 'raw-$BASE', 'VIA_RAW' => 'raw-$BASE',
                                                    'UNKNOWN' => '[]', 'DOLLARS' => 'a$b')
    end

    it 'joins before_script and script into one main script, multi-line entries intact' do
      yaml = <<~YAML
        default:
          before_script: [echo before]
        job:
          script:
            - echo one
            - |
              echo two
              echo three
          after_script: [echo after]
      YAML
      environment = job(yaml, 'job')
      expect(environment.main_script).to eq("echo before\necho one\necho two\necho three\n")
      expect(environment.after_script).to eq('echo after')
    end

    it 'has no after_script when none is configured' do
      expect(job("job: {script: [echo]}\n", 'job').after_script).to be_nil
    end

    it 'gives after_script the outcome as CI_JOB_STATUS and nothing else' do
      environment = job("job: {script: [echo]}\n", 'job')
      expect(environment.after_script_variables('failed')).to eq(environment.variables.merge('CI_JOB_STATUS' => 'failed'))
      expect { environment.after_script_variables('running') }.to raise_error(ArgumentError, /CI_JOB_STATUS/)
    end

    it 'rejects a variable name a shell cannot export' do
      expect { job("job: {script: [echo]}\n", 'job', cli: { 'BAD-NAME' => 'x' }) }
        .to raise_error(JobEnvironment::Error, /variable name 'BAD-NAME'/)
    end

    it 'reads RUNNER_AFTER_SCRIPT_TIMEOUT from the job variables' do
      yaml = "job: {variables: {RUNNER_AFTER_SCRIPT_TIMEOUT: 90s}, script: [echo]}\n"
      expect(job(yaml, 'job').after_script_timeout_s).to eq(90)
    end
  end
end
