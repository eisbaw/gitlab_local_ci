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

# script/before_script/after_script validation (upstream Entry::Commands,
# StringOrNestedArrayOfStringsValidator max_level 10), TASK-38.
RSpec.describe PipelineBuilder, '.commands_errors' do
  around do |example|
    Dir.mktmpdir('pipeline_commands') do |dir|
      @dir = dir
      example.run
    end
  end

  def errors(yaml)
    File.write(File.join(@dir, '.gitlab-ci.yml'), yaml)
    context = PipelineBuilder::Context.new(project_dir: @dir, gitlab_dir: nil,
                                           pipeline_source: PinnedPipelineContext::PIPELINE_SOURCE,
                                           variables: PinnedPipelineContext::VARIABLES)
    PipelineBuilder.resolve_config(File.join(@dir, '.gitlab-ci.yml'), context).errors
  end

  def message(location)
    "#{location} config should be a string or a nested array of strings up to 10 levels deep"
  end

  def nested(depth)
    depth.times.reduce('echo deep') { |inner, _| [inner] }
  end

  it 'accepts a string, a list of strings and nested lists up to 10 levels' do
    expect(errors("a:\n  script: echo a\n")).to eq([])
    expect(errors("a:\n  script: [echo a, [echo b]]\n")).to eq([])
    expect(errors({ 'a' => { 'script' => nested(10) } }.to_yaml)).to eq([])
  end

  it 'rejects lists nested deeper than 10 levels' do
    expect(errors({ 'a' => { 'script' => nested(11) } }.to_yaml)).to eq([message('jobs:a:script')])
  end

  it 'rejects mapping and non-string scalar entries, at every location upstream validates' do
    yaml = <<~YAML
      before_script:
        - echo "root: x"
      after_script: [42]
      default:
        before_script:
          - echo "default: x"
        after_script: true
      Build:
        before_script: [{a: b}]
        script:
          - echo "Coverage: 85%"
        after_script: [ok, [null]]
    YAML

    expect(errors(yaml)).to eq([
                                 message('before_script'), message('after_script'),
                                 message('default:before_script'), message('default:after_script'),
                                 message('jobs:build:before_script'), message('jobs:build:script'),
                                 message('jobs:build:after_script')
                               ])
  end

  it 'does not validate hidden jobs, and treats a null key as unspecified' do
    expect(errors(".template:\n  script:\n    - echo \"a: b\"\njob:\n  script: echo\n  after_script:\n")).to eq([])
  end

  it 'validates what a job ends up with after extends: and !reference' do
    yaml = <<~YAML
      .base:
        script:
          - echo "inherited: bad"
      job:
        extends: .base
      other:
        script:
          - !reference [.base, script]
    YAML

    expect(errors(yaml)).to eq([message('jobs:job:script'), message('jobs:other:script')])
  end
end
