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
require 'include_processor'

# The SSRF check of include:remote (TASK-74) for every other download:
# component hosts, project/template fetches and every redirect hop are
# address-checked and pinned before connecting. Only the user's GitLab
# instance (CI_SERVER_URL / origin), same host and port, is exempt.
# DNS and the network are faked; connections records each TCP target.
RSpec.describe ExternalResourceCache, 'download address check' do
  around do |example|
    Dir.mktmpdir('download-ssrf') do |dir|
      @dir = dir
      example.run
    end
  end

  let(:dns) { { 'public.example' => %w[93.184.215.14], 'gitlab.com' => %w[172.65.251.78] } }
  let(:connections) { [] }
  let(:responses) { {} }

  def ok(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response['content-type'] = 'text/plain'
    allow(response).to receive(:body).and_return(body)
    response
  end

  def redirect(location)
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    response['location'] = location
    response
  end

  before do
    allow(Resolv).to receive(:getaddresses) { |name| dns.fetch(name, []) }
    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      connections << { host: host, port: port, ipaddr: options[:ipaddr] }
      connection = double('http')
      allow(connection).to receive(:request) do |request|
        responses.fetch("#{host}#{request.path}") { ok("job:\n  script: echo\n") }
      end
      block.call(connection)
    end
  end

  def include_component(reference, server_url: 'https://gitlab.com')
    IncludeProcessor.new(project_path: @dir, cache_root: File.join(@dir, 'cache'), server_url: server_url)
                    .process_includes('include' => [{ 'component' => reference }])
  end

  it 'refuses a component on 127.0.0.1 before connecting' do
    expect { include_component('127.0.0.1:18443/g/c@1.0') }.to raise_error(/non-public address \(127\.0\.0\.1\)/)
    expect(connections).to eq([])
  end

  it 'refuses a component on a host name that resolves to ::1' do
    dns['sneaky.example'] = %w[::1]
    expect { include_component('sneaky.example/g/c@1.0') }.to raise_error(/non-public address \(::1\)/)
    expect(connections).to eq([])
  end

  it 'fetches a component from a public host, pinned to the checked address' do
    include_component('public.example/g/c@1.0')
    expect(connections).to eq([{ host: 'public.example', port: 443, ipaddr: '93.184.215.14' }])
  end

  it 'refuses a redirect from a public host to 169.254.169.254, before connecting to it' do
    responses['public.example/g/c/-/raw/1.0/template.yml'] = redirect('https://169.254.169.254/latest/meta-data/')

    expect { include_component('public.example/g/c@1.0') }.to raise_error(/non-public address \(169\.254\.169\.254\)/)
    expect(connections.map { |c| c[:host] }).to eq(%w[public.example])
  end

  it 'refuses a redirect from the trusted instance to another private host' do
    dns['gitlab.internal'] = %w[10.1.2.3]
    dns['other.internal'] = %w[10.9.9.9]
    responses['gitlab.internal/g/p/-/raw/v1/ci.yml'] = redirect('https://other.internal/x')
    cache = described_class.new(cache_root: File.join(@dir, 'cache'))

    expect { cache.fetch_project_file('g/p', 'ci.yml', ref: 'v1', server_url: 'https://gitlab.internal') }
      .to raise_error(/non-public address \(10\.9\.9\.9\)/)
    expect(connections.map { |c| c[:host] }).to eq(%w[gitlab.internal])
  end

  it 'still fetches a project file from a user-set private CI_SERVER_URL, and its same-host redirects' do
    dns['gitlab.internal'] = %w[10.1.2.3]
    responses['gitlab.internal/g/p/-/raw/v1/ci.yml'] = redirect('/g/p/-/raw/abc123/ci.yml')
    cache = described_class.new(cache_root: File.join(@dir, 'cache'))

    expect(cache.fetch_project_file('g/p', 'ci.yml', ref: 'v1', server_url: 'https://gitlab.internal'))
      .to eq("job:\n  script: echo\n")
    expect(connections).to eq([{ host: 'gitlab.internal', port: 443, ipaddr: nil }] * 2)
  end

  it 'exempts a component on the instance itself, but not another port of it' do
    dns['gitlab.internal'] = %w[10.1.2.3]
    include_component('gitlab.internal/g/c@1.0', server_url: 'https://gitlab.internal')
    expect(connections).to eq([{ host: 'gitlab.internal', port: 443, ipaddr: nil }])

    expect { include_component('gitlab.internal:6379/g/c@1.0', server_url: 'https://gitlab.internal') }
      .to raise_error(/non-public address \(10\.1\.2\.3\)/)
    expect(connections.size).to eq(1)
  end

  it 'checks templates from gitlab.com like any other host' do
    dns['gitlab.com'] = %w[127.0.0.1]
    cache = described_class.new(cache_root: File.join(@dir, 'cache'))
    expect { cache.fetch_template('Foo.gitlab-ci.yml') }.to raise_error(/non-public address/)
    expect(connections).to eq([])
  end
end
