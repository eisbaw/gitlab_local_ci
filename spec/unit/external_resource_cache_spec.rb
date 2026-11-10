# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
require 'spec_helper'
require 'external_resource_cache'
require 'tmpdir'

# The network is the only thing faked: Net::HTTP.start yields a fake
# connection that answers from a URL => response table and records every
# URL asked for. Everything else (lookup order, cache files, redirects,
# error texts) is the real code.
RSpec.describe ExternalResourceCache do
  around do |example|
    Dir.mktmpdir('ext-cache') do |dir|
      @dir = dir
      example.run
    end
  end

  let(:cache) { described_class.new(cache_root: File.join(@dir, 'cache')) }
  let(:requested_urls) { [] }
  let(:responses) { {} }

  def http_response(klass, code, body: '', headers: {})
    response = klass.new('1.1', code, 'msg')
    headers.each { |name, value| response[name] = value }
    allow(response).to receive(:body).and_return(body)
    response
  end

  def ok(body, content_type: 'text/plain')
    http_response(Net::HTTPOK, '200', body: body, headers: { 'content-type' => content_type })
  end

  def redirect(location)
    http_response(Net::HTTPFound, '302', headers: { 'location' => location })
  end

  # Every host here is public (download_file address-checks each hop).
  before { allow(Resolv).to receive(:getaddresses).and_return(['93.184.215.14']) }

  before do
    allow(Net::HTTP).to receive(:start) do |host, port, **_options, &block|
      connection = double('http')
      allow(connection).to receive(:request) do |request|
        url = "https://#{host}#{port == 443 ? '' : ":#{port}"}#{request.path}"
        requested_urls << url
        responses.fetch(url) { http_response(Net::HTTPNotFound, '404') }
      end
      block.call(connection)
    end
  end

  let(:template_url) { 'https://gitlab.com/gitlab-org/gitlab/-/raw/master/lib/gitlab/ci/templates/Foo.gitlab-ci.yml' }

  describe '#fetch_template' do
    it 'reads the local GitLab checkout first and never touches the network' do
      templates = File.join(@dir, 'templates')
      FileUtils.mkdir_p(templates)
      File.write(File.join(templates, 'Foo.gitlab-ci.yml'), "local: true\n")

      expect(cache.fetch_template('Foo.gitlab-ci.yml', gitlab_templates_path: templates)).to eq("local: true\n")
      expect(requested_urls).to be_empty
    end

    it 'downloads a missing template once, then serves it from the cache directory' do
      responses[template_url] = ok("downloaded: true\n")

      first = cache.fetch_template('Foo.gitlab-ci.yml', gitlab_templates_path: File.join(@dir, 'no-such-dir'))
      second = cache.fetch_template('Foo.gitlab-ci.yml')

      expect([first, second]).to eq(["downloaded: true\n"] * 2)
      expect(requested_urls).to eq([template_url])
      expect(File.read(File.join(@dir, 'cache', 'templates', 'Foo.gitlab-ci.yml'))).to eq("downloaded: true\n")
    end

    it 'follows a relative redirect' do
      responses[template_url] = redirect('/moved/Foo.yml')
      responses['https://gitlab.com/moved/Foo.yml'] = ok("moved: true\n")

      expect(cache.fetch_template('Foo.gitlab-ci.yml')).to eq("moved: true\n")
    end

    it 'gives up after a bounded number of redirects' do
      responses[template_url] = redirect(template_url)

      expect { cache.fetch_template('Foo.gitlab-ci.yml') }.to raise_error(/Too many redirects \(>5\)/)
      expect(requested_urls.size).to eq(6)
    end

    it 'refuses a redirect to plain http' do
      responses[template_url] = redirect('http://gitlab.com/Foo.yml')

      expect { cache.fetch_template('Foo.gitlab-ci.yml') }.to raise_error(/Insecure URL .* \(must use HTTPS\)/)
    end

    it 'treats an HTML answer (login page) as a failure and caches nothing' do
      responses[template_url] = ok('<html>sign in</html>', content_type: 'text/html; charset=utf-8')

      expect { cache.fetch_template('Foo.gitlab-ci.yml') }.to raise_error(/HTML response/)
      expect(File.exist?(File.join(@dir, 'cache', 'templates', 'Foo.gitlab-ci.yml'))).to be(false)
    end

    it 'reports the HTTP status of a failed download' do
      expect { cache.fetch_template('Foo.gitlab-ci.yml') }.to raise_error(/HTTP 404/)
    end
  end

  # TASK-75: one instance, never a fan-out: a private project path must not
  # reach hosts other than the instance the pipeline runs on.
  describe '#fetch_project_file' do
    it 'asks only the given instance and caches under instance/project/ref/file' do
      responses['https://gitlab.gnome.org/GNOME/app/-/raw/main/ci/base.yml'] = ok("base: true\n")

      2.times do
        content = cache.fetch_project_file('GNOME/app', 'ci/base.yml', ref: 'main', server_url: 'https://gitlab.gnome.org')
        expect(content).to eq("base: true\n")
      end
      expect(requested_urls).to eq(%w[https://gitlab.gnome.org/GNOME/app/-/raw/main/ci/base.yml])
      expect(File.read(File.join(@dir, 'cache', 'projects', 'gitlab.gnome.org', 'GNOME/app', 'main', 'ci/base.yml')))
        .to eq("base: true\n")
    end

    it 'keeps a non-default port and a relative URL root in the URL and the cache key' do
      url = 'https://git.example.com:8443/gitlab/group/app/-/raw/v1/x.yml'
      responses[url] = ok("x: 1\n")

      cache.fetch_project_file('group/app', 'x.yml', ref: 'v1', server_url: 'https://git.example.com:8443/gitlab/')

      expect(requested_urls).to eq([url])
      expect(File.exist?(File.join(@dir, 'cache', 'projects', 'git.example.com:8443/gitlab', 'group/app', 'v1', 'x.yml'))).to be(true)
    end

    it 'does not serve one instance\'s cached file for the same path on another' do
      responses['https://a.example/group/app/-/raw/v1/x.yml'] = ok("from: a\n")
      responses['https://b.example/group/app/-/raw/v1/x.yml'] = ok("from: b\n")

      expect(cache.fetch_project_file('group/app', 'x.yml', ref: 'v1', server_url: 'https://a.example')).to eq("from: a\n")
      expect(cache.fetch_project_file('group/app', 'x.yml', ref: 'v1', server_url: 'https://b.example')).to eq("from: b\n")
    end

    it 'names the one instance it asked when the file is not there, and asks no other' do
      expect { cache.fetch_project_file('group/app', 'x.yml', ref: 'v1', server_url: 'https://gitlab.example.com') }
        .to raise_error(%r{group/app/x.yml@v1 from GitLab instance https://gitlab.example.com \(--variables CI_SERVER_URL.*HTTP 404})
      expect(requested_urls).to eq(%w[https://gitlab.example.com/group/app/-/raw/v1/x.yml])
    end

    it 'rejects an HTML body served as text/plain (sign-in page) and caches nothing' do
      responses['https://gitlab.com/group/app/-/raw/v1/x.yml'] = ok("<!DOCTYPE html>\n<p>sign in</p>")

      expect { cache.fetch_project_file('group/app', 'x.yml', ref: 'v1', server_url: 'https://gitlab.com') }
        .to raise_error(/HTML/)
      expect(Dir.glob(File.join(@dir, 'cache', 'projects', '**', 'x.yml'))).to be_empty
    end

    ['http://gitlab.example.com', 'https://user:pw@gitlab.example.com', 'https://gitlab.example.com/../x',
     'gitlab.example.com', ''].each do |server_url|
      it "refuses instance URL #{server_url.inspect} before any request" do
        expect { cache.fetch_project_file('group/app', 'x.yml', ref: 'v1', server_url: server_url) }
          .to raise_error(/CI_SERVER_URL/)
        expect(requested_urls).to be_empty
      end
    end
  end

  describe '#fetch_component' do
    it 'downloads <fqdn>/<project>/-/raw/<version>/<file> and caches it per version' do
      url = 'https://gitlab.example.com/org/components/lint/-/raw/1.2.0/template.yml'
      responses[url] = ok("lint: {}\n")

      2.times { expect(cache.fetch_component('gitlab.example.com', 'org/components/lint', 'template.yml', '1.2.0')).to eq("lint: {}\n") }
      expect(requested_urls).to eq([url])
    end

    it 'fails with the component reference when the answer is an HTML page' do
      responses['https://gitlab.example.com/org/c/-/raw/1.0/template.yml'] = ok('<html></html>')

      expect { cache.fetch_component('gitlab.example.com', 'org/c', 'template.yml', '1.0') }
        .to raise_error(%r{Failed to download component gitlab.example.com/org/c/template.yml@1.0: .*HTML})
    end
  end
end
