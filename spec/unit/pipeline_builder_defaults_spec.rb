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

# default:, legacy top-level globals and inherit: through PipelineBuilder.
# Reference: gitlab/lib/gitlab/ci/config/entry/{default,root,job,bridge,
# processable,inherit}.rb, gitlab/lib/gitlab/config/entry/inheritable.rb,
# gitlab/lib/gitlab/ci/variables/helpers.rb#inherit_yaml_variables.
RSpec.describe PipelineBuilder do
  around do |example|
    Dir.mktmpdir('pipeline_defaults') do |dir|
      @dir = dir
      example.run
    end
  end

  def build(yaml, variables: {})
    File.write(File.join(@dir, '.gitlab-ci.yml'), yaml)
    context = PipelineBuilder::Context.new(project_dir: @dir, gitlab_dir: nil,
                                           pipeline_source: PinnedPipelineContext::PIPELINE_SOURCE,
                                           variables: PinnedPipelineContext::VARIABLES.merge(variables))
    PipelineBuilder.build(File.join(@dir, '.gitlab-ci.yml'), context)
  end

  def built(yaml, **opts)
    result = build(yaml, **opts)
    raise "unexpected errors: #{result.errors}" unless result.ok?

    result
  end

  def jobs(yaml)
    built(yaml).job_definitions
  end

  def pipeline_job_names(yaml, **opts)
    built(yaml, **opts).pipeline_jobs.keys
  end

  def errors(yaml)
    build(yaml).errors
  end

  describe 'default:' do
    it 'gives every visible job each key it does not set (audit_config/03 repro: tags)' do
      result = jobs(<<~YAML)
        default:
          tags: [nomatch]
          image: alpine
          before_script: [echo before]
          retry: 2
        job:
          script: [echo]
        other:
          image: ruby
          script: [echo]
      YAML
      expect(result['job']).to include('tags' => ['nomatch'], 'image' => 'alpine',
                                       'before_script' => ['echo before'], 'retry' => 2)
      expect(result['other']['image']).to eq('ruby')
      expect(result['other']['tags']).to eq(['nomatch'])
    end

    it 'applies every Entry::Default::ALLOWED_KEYS key' do
      default = CiKeywords::DEFAULT.to_h { |key| [key, "v-#{key}"] }
      yaml = { 'default' => default, 'job' => { 'script' => ['echo'] } }.to_yaml
      expect(jobs(yaml)['job']).to include(default)
    end

    it 'lets the job key replace the default whole, no deep merge (cache)' do
      result = jobs(<<~YAML)
        default:
          cache: {key: a, paths: [x]}
        job:
          script: [echo]
          cache: {paths: [y]}
      YAML
      expect(result['job']['cache']).to eq({ 'paths' => ['y'] })
    end

    it 'treats a null job key as unspecified, so the default applies' do
      expect(jobs(<<~YAML)['job']['image']).to eq('alpine')
        default: {image: alpine}
        job:
          image:
          script: [echo]
      YAML
    end

    it 'does not touch hidden templates, and leaves Result#config raw' do
      result = built(<<~YAML)
        default: {image: alpine}
        .tpl:
          script: [echo]
        job:
          script: [echo]
      YAML
      expect(result.job_definitions['.tpl']).not_to have_key('image')
      expect(result.config['job']).not_to have_key('image')
      expect(result.pipeline_jobs['job']['image']).to eq('alpine')
    end

    it 'counts a key from extends as the job\'s own, and defaults what the template lacks' do
      result = jobs(<<~YAML)
        default:
          image: alpine
          tags: [dflt]
        .tpl:
          image: ruby
          script: [echo]
        job:
          extends: .tpl
      YAML
      expect(result['job']).to include('image' => 'ruby', 'tags' => ['dflt'])
    end

    it 'applies a default that is a !reference as plain data' do
      expect(jobs(<<~YAML)['job']['before_script']).to eq(['echo setup'])
        .setup:
          script: [echo setup]
        default:
          before_script: !reference [.setup, script]
        job:
          script: [echo]
      YAML
    end

    it 'gives a trigger job only interruptible (Entry::Bridge)' do
      result = jobs(<<~YAML)
        default:
          tags: [x]
          image: alpine
          interruptible: true
        bridge:
          trigger: group/project
      YAML
      expect(result['bridge']).to eq('trigger' => 'group/project', 'interruptible' => true)
    end

    it 'rejects keys default: does not allow' do
      expect(errors("default: {stage: build}\njob:\n  script: [echo]\n"))
        .to eq(['default config contains unknown keys: stage'])
      expect(errors("default: [x]\njob:\n  script: [echo]\n")).to eq(['default config should be a hash'])
    end
  end

  describe 'legacy top-level globals' do
    it 'behave like default: for image, services, before_script, after_script and cache' do
      result = jobs(<<~YAML)
        image: alpine
        services: [postgres]
        before_script: [echo b]
        after_script: [echo a]
        cache: {paths: [c]}
        job:
          script: [echo]
      YAML
      expect(result['job']).to include('image' => 'alpine', 'services' => ['postgres'],
                                       'before_script' => ['echo b'], 'after_script' => ['echo a'],
                                       'cache' => { 'paths' => ['c'] })
    end

    it 'combine with default: when the keys differ' do
      expect(jobs(<<~YAML)['job']).to include('image' => 'alpine', 'tags' => ['t'])
        image: alpine
        default: {tags: [t]}
        job:
          script: [echo]
      YAML
    end

    it 'are an error when default: sets the same key (Entry::Default InheritError)' do
      expect(errors("image: alpine\ndefault: {image: ruby}\njob:\n  script: [echo]\n"))
        .to eq(['image is defined in top-level and `default:` entry'])
    end
  end

  describe 'inherit:default' do
    let(:defaults) { "default:\n  image: alpine\n  tags: [t]\n" }

    it 'false inherits nothing' do
      expect(jobs("#{defaults}job:\n  inherit: {default: false}\n  script: [echo]\n")['job'])
        .not_to include('image', 'tags')
    end

    it 'a list inherits only the listed keys' do
      job = jobs("#{defaults}job:\n  inherit: {default: [image]}\n  script: [echo]\n")['job']
      expect(job['image']).to eq('alpine')
      expect(job).not_to have_key('tags')
    end

    it 'also governs legacy globals' do
      expect(jobs("image: alpine\njob:\n  inherit: {default: false}\n  script: [echo]\n")['job'])
        .not_to have_key('image')
    end

    it 'rejects unknown values and shapes in upstream wording' do
      expect(errors("#{defaults}job:\n  inherit: {default: [stage]}\n  script: [echo]\n"))
        .to eq(['jobs:job:inherit:default config contains unknown values: stage'])
      expect(errors("#{defaults}job:\n  inherit: {default: yes_please}\n  script: [echo]\n"))
        .to eq(['jobs:job:inherit:default should be a bool or array of strings'])
      expect(errors("#{defaults}job:\n  inherit: {defaults: false}\n  script: [echo]\n"))
        .to eq(['jobs:job:inherit config contains unknown keys: defaults'])
      expect(errors("#{defaults}job:\n  inherit: false\n  script: [echo]\n"))
        .to eq(['jobs:job:inherit config should be a hash'])
    end
  end

  describe 'inherit:variables (what a job\'s rules see)' do
    def yaml(inherit)
      <<~YAML
        variables:
          G: '1'
          H: '1'
        job:
          script: [echo]
          #{inherit}
          rules:
            - if: $G == "1"
      YAML
    end

    it 'true (absent) lets top-level variables reach the rules' do
      expect(pipeline_job_names(yaml(''))).to eq(['job'])
    end

    it 'false hides every top-level variable from the rules' do
      expect(pipeline_job_names(yaml('inherit: {variables: false}'))).to eq([])
    end

    it 'a list lets only the listed variables through' do
      expect(pipeline_job_names(yaml('inherit: {variables: [G]}'))).to eq(['job'])
      expect(pipeline_job_names(yaml('inherit: {variables: [H]}'))).to eq([])
    end

    it 'does not filter CLI (pipeline) variables' do
      expect(pipeline_job_names(yaml('inherit: {variables: false}'), variables: { 'G' => '1' })).to eq(['job'])
    end

    it 'filters workflow:rules:variables too (they are root variables)' do
      expect(pipeline_job_names(<<~YAML)).to eq(['inherits'])
        workflow:
          rules:
            - variables: {W: '1'}
        inherits:
          script: [echo]
          rules:
            - if: $W == "1"
        isolated:
          script: [echo]
          inherit: {variables: false}
          rules:
            - if: $W == "1"
      YAML
    end

    it 'rejects a non bool/list value' do
      expect(errors(yaml('inherit: {variables: G}')))
        .to eq(['jobs:job:inherit:variables should be a bool or array of strings'])
    end
  end
end
