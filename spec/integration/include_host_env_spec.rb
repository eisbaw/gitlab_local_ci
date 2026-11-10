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
require 'tmpdir'
require 'json'
require 'include_processor'
require_relative '../support/pinned_pipeline_context'

# TASK-78: $CI_SERVER_* in include paths come from the builder's variables
# (--variables, else the instance TASK-75 picks), never from the host
# environment of the tool.
RSpec.describe 'include paths and host CI_SERVER_* variables' do
  # In-process: which fqdn a component reference expands to. The cache is
  # stubbed, so nothing is fetched.
  describe IncludeProcessor do
    let(:asked) { [] }

    before do
      allow_any_instance_of(ExternalResourceCache).to receive(:fetch_component) do |_cache, fqdn, project, _file, version|
        asked << "#{fqdn}/#{project}@#{version}"
        "component_job:\n  script: echo c\n"
      end
    end

    def expand(server_url:, variables: {}, component: '$CI_SERVER_FQDN/group/comp@1.0')
      Dir.mktmpdir do |dir|
        described_class.new(project_path: dir, cache_root: File.join(dir, 'cache'), server_url: server_url,
                            variables: variables).process_includes('include' => [{ 'component' => component }])
      end
      asked.last
    end

    around do |example|
      saved = %w[CI_SERVER_URL CI_SERVER_HOST CI_SERVER_FQDN].to_h { |name| [name, ENV.fetch(name, nil)] }
      ENV.update('CI_SERVER_URL' => 'https://host-env.example', 'CI_SERVER_HOST' => 'host-env.example',
                 'CI_SERVER_FQDN' => 'host-env.example')
      example.run
    ensure
      ENV.update(saved)
    end

    it 'expands to the instance, ignoring the process environment' do
      expect(expand(server_url: 'https://gitlab.gnome.org')).to eq('gitlab.gnome.org/group/comp@1.0')
    end

    it 'keeps a non-default port in CI_SERVER_FQDN, not in CI_SERVER_HOST' do
      expect(expand(server_url: 'https://git.example.com:8443')).to eq('git.example.com:8443/group/comp@1.0')
      expect(expand(server_url: 'https://git.example.com:8443', component: '${CI_SERVER_HOST}/group/comp@1.0'))
        .to eq('git.example.com/group/comp@1.0')
    end

    it 'takes CI_SERVER_HOST and CI_SERVER_FQDN from --variables when set' do
      expect(expand(server_url: 'https://gitlab.com', variables: { 'CI_SERVER_FQDN' => 'cli.example' }))
        .to eq('cli.example/group/comp@1.0')
    end

    it 'does not expand a longer name that starts with one of them' do
      expect(expand(server_url: 'https://gitlab.com', component: 'gitlab.com/$CI_SERVER_HOSTX/c@1.0'))
        .to eq('gitlab.com/$CI_SERVER_HOSTX/c@1.0')
    end
  end

  # The spawned CLI, with CI_SERVER_* set in its environment as inside a
  # CI job on another instance. The component is pre-cached for gitlab.com
  # (the instance with no origin and no --variables). The network is cut by
  # a proxy on a closed local port: if the host value leaked, the CLI would
  # look for host-env.example, miss the cache and fail to connect.
  describe 'bin/gitlab_ci_cli' do
    let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }
    let(:host_env) do
      { 'CI_SERVER_URL' => 'https://host-env.example', 'CI_SERVER_HOST' => 'host-env.example',
        'CI_SERVER_FQDN' => 'host-env.example', 'https_proxy' => 'http://127.0.0.1:9',
        'HTTPS_PROXY' => 'http://127.0.0.1:9', 'no_proxy' => nil, 'NO_PROXY' => nil }
    end

    def lint(dir, *args)
      Open3.capture3(host_env, bin_path, 'lint', '--entry', File.join(dir, 'app', '.gitlab-ci.yml'), '--format', 'json',
                     *PinnedPipelineContext::CLI_ARGS, *args, chdir: dir)
    end

    def layout(dir, cached_fqdn)
      FileUtils.mkdir_p(File.join(dir, 'app'))
      system('git', '-C', File.join(dir, 'app'), 'init', '-q', exception: true)
      File.write(File.join(dir, 'app', '.gitlab-ci.yml'), <<~YAML)
        include:
          - component: $CI_SERVER_FQDN/group/comp@1.0
        job:
          script: echo
      YAML
      cached = File.join(dir, 'ext_tmp', 'components', cached_fqdn, 'group/comp', '1.0', 'template.yml')
      FileUtils.mkdir_p(File.dirname(cached))
      File.write(cached, "component_job:\n  script: echo c\n")
    end

    it 'resolves $CI_SERVER_FQDN to gitlab.com, not to the host environment' do
      Dir.mktmpdir do |dir|
        layout(dir, 'gitlab.com')
        stdout, stderr, status = lint(dir)

        expect(stderr).to eq('')
        expect(status.success?).to be(true), stdout
        expect(JSON.parse(stdout)['jobs']).to include('component_job')
      end
    end

    it 'resolves it to --variables CI_SERVER_URL when given' do
      Dir.mktmpdir do |dir|
        layout(dir, 'gitlab.example.com:8443')
        stdout, _stderr, status = lint(dir, '--variables', 'CI_SERVER_URL=https://gitlab.example.com:8443')

        expect(status.success?).to be(true), stdout
        expect(JSON.parse(stdout)['jobs']).to include('component_job')
      end
    end
  end
end
