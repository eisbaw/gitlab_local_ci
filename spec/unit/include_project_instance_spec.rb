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
require_relative '../support/pinned_pipeline_context'

# TASK-75: include:project is fetched from exactly one GitLab instance:
# --variables CI_SERVER_URL, else the origin remote's host, else
# gitlab.com. Driven through PipelineBuilder (the integration site) with a
# real git checkout; only the network is faked. Net::HTTP.start records the
# host of every connection and answers 200 with a job, so a fan-out would
# show up as more than one host.
RSpec.describe PipelineBuilder, 'include:project instance' do
  around do |example|
    Dir.mktmpdir('project-instance') do |dir|
      @dir = dir
      @project = File.join(dir, 'app')
      FileUtils.mkdir_p(@project)
      File.write(File.join(@project, '.gitlab-ci.yml'), <<~YAML)
        include:
          - project: private-group/secret-lib
            ref: v1
            file: ci.yml
        job:
          script: echo
      YAML
      git('init', '-q', '-b', 'main')
      # The download cache lives in ./ext_tmp; keep it out of the repo.
      Dir.chdir(dir) { example.run }
    end
  end

  let(:hosts) { [] }

  before do
    allow(Net::HTTP).to receive(:start) do |host, _port, **_options, &block|
      hosts << host
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      response['content-type'] = 'text/plain'
      allow(response).to receive(:body).and_return("included_job:\n  script: echo i\n")
      block.call(double('http', request: response))
    end
  end

  def git(*args)
    _out, err, status = Open3.capture3('git', '-C', @project, *args)
    raise "git #{args.join(' ')}: #{err}" unless status.success?
  end

  def resolve(variables = {})
    result = described_class.resolve_config(File.join(@project, '.gitlab-ci.yml'),
                                            PinnedPipelineContext.context(@project, variables: variables))
    expect(result.errors).to eq([])
    result
  end

  it 'uses --variables CI_SERVER_URL, over the origin remote' do
    git('remote', 'add', 'origin', 'git@gitlab.gnome.org:GNOME/app.git')

    expect(resolve('CI_SERVER_URL' => 'https://gitlab.example.com').config).to include('included_job')
    expect(hosts).to eq(%w[gitlab.example.com])
  end

  it 'uses the origin remote host without CI_SERVER_URL' do
    git('remote', 'add', 'origin', 'https://deploy:token@gitlab.freedesktop.org/mesa/mesa.git')

    resolve
    expect(hosts).to eq(%w[gitlab.freedesktop.org])
  end

  it 'falls back to gitlab.com with neither, and only gitlab.com even when it lacks the file' do
    resolve
    expect(hosts).to eq(%w[gitlab.com])

    hosts.clear
    FileUtils.rm_rf(File.join(@dir, 'ext_tmp'))
    allow(Net::HTTP).to receive(:start) do |host, *_rest, &block|
      hosts << host
      block.call(double('http', request: Net::HTTPNotFound.new('1.1', '404', 'Not Found')))
    end
    result = described_class.resolve_config(File.join(@project, '.gitlab-ci.yml'), PinnedPipelineContext.context(@project))
    expect(result.errors.join).to include('from GitLab instance https://gitlab.com ')
    expect(hosts).to eq(%w[gitlab.com])
  end

  it 'names the one instance in the error and asks no other' do
    allow(Net::HTTP).to receive(:start) do |host, *_rest|
      hosts << host
      raise Errno::ECONNREFUSED, host
    end
    git('remote', 'add', 'origin', 'git@gitlab.gnome.org:GNOME/app.git')

    result = described_class.resolve_config(File.join(@project, '.gitlab-ci.yml'), PinnedPipelineContext.context(@project))
    expect(result.errors.join).to include('from GitLab instance https://gitlab.gnome.org (--variables CI_SERVER_URL')
    expect(hosts).to eq(%w[gitlab.gnome.org])
  end
end
