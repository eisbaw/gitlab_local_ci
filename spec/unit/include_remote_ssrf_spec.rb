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

# TASK-74: include:remote must not reach this host or its network. DNS and
# the network are faked: the resolver answers from a table (getaddress is
# the first entry of getaddresses, as in Resolv), and Net::HTTP.start
# records what it was asked to connect to and answers 200 with a job.
RSpec.describe IncludeProcessor, 'include:remote address check' do
  around do |example|
    Dir.mktmpdir('remote-ssrf') do |dir|
      @dir = dir
      example.run
    end
  end

  let(:dns) { {} }
  let(:connections) { [] }
  let(:processor) { described_class.new(project_path: @dir, cache_root: File.join(@dir, 'cache')) }

  before do
    allow(Resolv).to receive(:getaddresses) { |name| dns.fetch(name, []) }
    allow(Resolv).to receive(:getaddress) do |name|
      dns.fetch(name, []).first or raise Resolv::ResolvError, "no address for #{name}"
    end
    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      connections << { host: host, port: port, ipaddr: options[:ipaddr] }
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return("remote_job:\n  script: echo r\n")
      connection = double('http', request: response)
      block.call(connection)
    end
  end

  def include_remote(url)
    processor.process_includes('include' => [{ 'remote' => url }], 'job' => { 'script' => 'x' })
  end

  def expect_refused(url, *addresses)
    expect { include_remote(url) }.to raise_error(RuntimeError) { |error|
      expect(error.message).to include('non-public address')
      addresses.each { |address| expect(error.message).to include(address) }
    }
    expect(connections).to be_empty
  end

  it 'refuses localhost that resolves to ::1 first (the reported case)' do
    dns['localhost'] = %w[::1 127.0.0.1]
    expect_refused('https://localhost:9/x.yml', '::1', '127.0.0.1')
  end

  it 'refuses a name whose answer mixes a public and a private address' do
    dns['mixed.example'] = %w[93.184.215.14 10.0.0.5]
    expect_refused('https://mixed.example/ci.yml', '10.0.0.5')
  end

  it 'refuses an IPv4-mapped IPv6 loopback' do
    dns['mapped.example'] = %w[::ffff:127.0.0.1]
    expect_refused('https://mapped.example/ci.yml', '::ffff:127.0.0.1')
  end

  it 'refuses an IPv6 unique local address' do
    dns['ula.example'] = %w[fc00::1]
    expect_refused('https://ula.example/ci.yml', 'fc00::1')
  end

  it 'refuses the cloud metadata service on IPv4 and on IPv6 (AWS fd00:ec2::254)' do
    dns['metadata.example'] = %w[169.254.169.254]
    dns['metadata6.example'] = %w[fd00:ec2::254]
    expect_refused('https://metadata.example/latest', '169.254.169.254')
    expect_refused('https://metadata6.example/latest', 'fd00:ec2::254')
  end

  it 'refuses a literal [::1] URL without a DNS lookup' do
    expect_refused('https://[::1]:9/x.yml', '::1')
    expect(Resolv).not_to have_received(:getaddresses)
  end

  it 'refuses a name that resolves to nothing' do
    expect { include_remote('https://nothing.example/ci.yml') }.to raise_error(/Cannot resolve hostname 'nothing.example'/)
    expect(connections).to be_empty
  end

  it 'fetches from a public host, connecting to the address it checked' do
    dns['ci.example'] = %w[93.184.215.14 2606:2800:21f:cb07:6820:80da:af6b:8b2c]

    expect(include_remote('https://ci.example/ci.yml').keys).to include('remote_job', 'job')
    expect(connections).to eq([{ host: 'ci.example', port: 443, ipaddr: '93.184.215.14' }])
  end

  # Independent oracle: ranges written out here, not taken from the code.
  # Random addresses inside each range, and IPv4 ones also IPv4-mapped,
  # IPv4-compatible and NAT64-embedded, are all refused.
  describe 'every non-public range' do
    ipv4 = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
              192.168.0.0/16 224.0.0.0/4 240.0.0.0/4]
    ipv6 = %w[::1/128 ::/128 fc00::/7 fe80::/10 ff00::/8]
    random = Random.new(74)
    sample = lambda do |cidr|
      range = IPAddr.new(cidr).to_range
      Array.new(5) { IPAddr.new(random.rand(range.first.to_i..range.last.to_i), range.first.family).to_s }
    end

    (ipv4 + ipv6).each do |cidr|
      it "refuses #{cidr}" do
        sample.call(cidr).each do |address|
          forms = [address]
          forms += ["::ffff:#{address}", "64:ff9b::#{address}"] if IPAddr.new(address).ipv4?
          forms.each do |form|
            dns['h.example'] = [form]
            expect { include_remote('https://h.example/ci.yml') }.to raise_error(/non-public address/), form
          end
        end
        expect(connections).to be_empty
      end
    end

    it 'allows public addresses, also NAT64-embedded' do
      %w[8.8.8.8 64:ff9b::808:808 2a00:1450:4001::1].each do |address|
        dns['h.example'] = [address]
        expect { include_remote('https://h.example/ci.yml') }.not_to raise_error
      end
    end
  end
end
