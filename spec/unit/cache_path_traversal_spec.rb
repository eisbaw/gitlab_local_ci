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

# Every download cache path (templates, projects, components; read and
# write) is built from config-controlled names. None may leave the cache
# root. The network is faked: every request answers 200 with a job, so a
# traversal shows up as a file written outside the root, or a planted file
# outside it read back.
RSpec.describe ExternalResourceCache, 'cache paths stay under the cache root' do
  around do |example|
    Dir.mktmpdir('cache-traversal') do |dir|
      @dir = dir
      example.run
    end
  end

  let(:cache_root) { File.join(@dir, 'sandbox', 'cache') }
  let(:cache) { described_class.new(cache_root: cache_root) }
  let(:requests) { [] }

  before do
    allow(Net::HTTP).to receive(:start) do |host, *_rest, &block|
      requests << host
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      response['content-type'] = 'text/plain'
      allow(response).to receive(:body).and_return("pwned_job:\n  script: echo pwned\n")
      block.call(double('http', request: response))
    end
  end

  # Every file under @dir that is not under the cache root.
  def files_outside_cache_root
    Dir.glob(File.join(@dir, '**', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }
       .reject { |path| path.start_with?(cache_root + File::SEPARATOR) }
  end

  describe 'include: component (the reported repro)' do
    let(:processor) { IncludeProcessor.new(project_path: File.join(@dir, 'sandbox'), cache_root: cache_root) }

    def include_component(reference)
      processor.process_includes('include' => [{ 'component' => reference }], 'job' => { 'script' => 'x' })
    end

    # cache/components/evil.example/a/../../../../outside/x/v1/template.yml
    # is @dir/sandbox/outside/... on a naive File.join; one more .. is @dir.
    let(:reference) { 'evil.example/a/../../../../../outside/x@v1' }

    it 'writes nothing outside the cache root' do
      expect { include_component(reference) }.to raise_error(/Failed to fetch component.*'\.\.'/)
      expect(files_outside_cache_root).to eq([])
      expect(requests).to eq([])
    end

    it 'does not read a template.yml planted outside the cache root' do
      planted = File.join(@dir, 'outside', 'x', 'v1', 'template.yml')
      FileUtils.mkdir_p(File.dirname(planted))
      File.write(planted, "planted_job:\n  script: echo planted\n")

      expect { include_component(reference) }.to raise_error(/'\.\.'/)
    end
  end

  describe 'every name that becomes a path segment' do
    {
      'project with ..' => -> (c) { c.fetch_project_file('g/../../../../../x', 'f.yml', ref: 'v1', server_url: 'https://h.example') },
      'ref with ..' => -> (c) { c.fetch_project_file('g/p', 'f.yml', ref: '../../../../../x', server_url: 'https://h.example') },
      'file with ..' => -> (c) { c.fetch_project_file('g/p', '../../../../../../x.yml', ref: 'v1', server_url: 'https://h.example') },
      'absolute file' => -> (c) { c.fetch_project_file('g/p', '/etc/x.yml', ref: 'v1', server_url: 'https://h.example') },
      'absolute project' => -> (c) { c.fetch_project_file('/g/p', 'f.yml', ref: 'v1', server_url: 'https://h.example') },
      'backslash in a ref' => -> (c) { c.fetch_project_file('g/p', 'f.yml', ref: '..\\..\\x', server_url: 'https://h.example') },
      'NUL in a file' => -> (c) { c.fetch_project_file('g/p', "f\0.yml", ref: 'v1', server_url: 'https://h.example') },
      '. segment' => -> (c) { c.fetch_project_file('g/./p', 'f.yml', ref: 'v1', server_url: 'https://h.example') },
      'template with ..' => -> (c) { c.fetch_template('../../../../x.yml') },
      'component fqdn ..' => -> (c) { c.fetch_component('..', 'g/p', 'template.yml', 'v1') },
      'component version ..' => -> (c) { c.fetch_component('h.example', 'g/p', 'template.yml', '..') }
    }.each do |name, fetch|
      it "refuses #{name} before any request, writing nothing outside" do
        expect { fetch.call(cache) }.to raise_error(RuntimeError, /cache path/)
        expect(requests).to eq([])
        expect(files_outside_cache_root).to eq([])
      end
    end

    it 'still caches ordinary names' do
      cache.fetch_project_file('group/sub/app', 'ci/base.yml', ref: 'v1.2', server_url: 'https://h.example:8443/gitlab')
      cache.fetch_component('gitlab.example.com', 'org/comp', 'template.yml', '1.0.0')
      expect(Dir.glob(File.join(cache_root, '**', '*.yml')).map { |path| path.delete_prefix(cache_root) }).to contain_exactly(
        '/projects/h.example:8443/gitlab/group/sub/app/v1.2/ci/base.yml',
        '/components/gitlab.example.com/org/comp/1.0.0/template.yml'
      )
    end
  end
end
