# frozen_string_literal: true

require 'spec_helper'
require 'mock_server'

RSpec.describe MockServer, 'workflow:rules: cascade and per-rule attributes' do
  let(:config_yaml) do
    <<~YAML
      workflow:
        rules:
          - if: '$KIND == "skip"'
            when: never
          - if: '$KIND == "submodule"'
            variables:
              ENABLE_SMOKE: "false"
              PIPELINE_NAME: "submodule"
          - when: always
            variables:
              PIPELINE_NAME: "default"

      variables:
        ENABLE_SMOKE: "true"

      build:
        script: ["echo build"]
        rules:
          - if: '$ENABLE_SMOKE == "true"'

      smoke:
        script: ["echo smoke"]
        rules:
          - if: '$ENABLE_SMOKE == "true"'
            variables:
              SMOKE_VARIANT: "fast"
              allow_failure: true
          - when: never

      maintenance:
        script: ["echo m"]
        rules:
          - if: '$KIND == "submodule"'
    YAML
  end

  it 'cascades workflow rule variables into job rule evaluation' do
    # KIND=submodule => ENABLE_SMOKE flips to "false", so build/smoke drop.
    server = MockServer.new(project_dir: Dir.mktmpdir, pipeline_source: 'push')
    pipeline = server.create_pipeline(config_yaml, variables: { 'KIND' => 'submodule' })
    job_names = pipeline.jobs.map(&:name)
    expect(job_names).to include('maintenance')
    expect(job_names).not_to include('build')
    expect(job_names).not_to include('smoke')
  end

  it 'raises WorkflowRulesFilteredError when no workflow rule matches' do
    # Use a config whose workflow rules ALL miss + when:never on match.
    cfg = <<~YAML
      workflow:
        rules:
          - if: '$X == "1"'
      job:
        script: ["echo"]
    YAML
    server = MockServer.new(project_dir: Dir.mktmpdir, pipeline_source: 'push')
    expect do
      server.create_pipeline(cfg, variables: {})
    end.to raise_error(MockServer::WorkflowRulesFilteredError, /workflow:rules: matched no rule/)
  end

  it 'merges per-rule variables into the matched job' do
    server = MockServer.new(project_dir: Dir.mktmpdir, pipeline_source: 'push')
    pipeline = server.create_pipeline(config_yaml, variables: {})
    smoke = pipeline.jobs.find { |j| j.name == 'smoke' }
    expect(smoke).not_to be_nil
    # smoke job's rule attached `variables.SMOKE_VARIANT = fast`
    # MockJob's variables hash is exposed on the underlying config — we
    # validate by reading job.variables (MockJob preserves it).
    expect(smoke.respond_to?(:variables) ? smoke.variables : nil).to include('SMOKE_VARIANT' => 'fast')
  end
end
