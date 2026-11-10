# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'net/http'
require 'uri'
require 'fileutils'
require 'openssl'

# ExternalResourceCache manages downloading and caching of external GitLab resources
#
# This class handles:
# - GitLab CI templates from gitlab.com
# - Project files from the one GitLab instance the caller names
#   (CI_SERVER_URL); never from any other host, so a private project path
#   is not sent elsewhere
# - Components from the host their reference names
# - Local caching in ext_tmp/
# - Fallback mechanisms when local resources aren't available
#
# MPED Principles:
# - Explicit caching: Cache location and behavior is transparent
# - Fail-fast: Network errors are reported immediately
# - Simple file structure: Mirrors GitLab's structure for clarity
# - No magic: Downloads only when explicitly needed
class ExternalResourceCache
  # Base URL for GitLab.com
  GITLAB_COM_URL = 'https://gitlab.com'

  # GitLab repository that contains CI templates
  GITLAB_REPO = 'gitlab-org/gitlab'

  # Default branch for fetching templates
  DEFAULT_BRANCH = 'master'

  # Cache directory
  CACHE_DIR = 'ext_tmp'

  # Timeout for HTTP requests (seconds)
  HTTP_TIMEOUT = 10

  attr_reader :cache_root

  # Initialize the cache
  #
  # @param cache_root [String] Root directory for cache (default: ext_tmp)
  def initialize(cache_root: CACHE_DIR)
    @cache_root = cache_root
    ensure_cache_directories
  end

  # Fetch a GitLab CI template
  #
  # Attempts to retrieve template in this order:
  # 1. Local gitlab submodule (if provided)
  # 2. Local cache (ext_tmp/templates/)
  # 3. Download from gitlab.com
  #
  # @param template_name [String] Template path (e.g., "Jobs/Dependency-Scanning.latest.gitlab-ci.yml")
  # @param gitlab_templates_path [String, nil] Path to local GitLab templates
  # @return [String] Template content
  # @raise [RuntimeError] If template cannot be fetched
  def fetch_template(template_name, gitlab_templates_path: nil)
    # First: its segment checks also keep the checkout lookup below inside
    # gitlab_templates_path.
    cache_path = template_cache_path(template_name)

    # Strategy 1: Check local gitlab submodule
    if gitlab_templates_path
      local_path = File.join(gitlab_templates_path, template_name)
      if File.exist?(local_path)
        return File.read(local_path)
      end
    end

    # Strategy 2: Check local cache
    if File.exist?(cache_path)
      return File.read(cache_path)
    end

    # Strategy 3: Download from gitlab.com
    download_template(template_name)
  end

  # Fetch a file from another project on the GitLab instance server_url
  #
  # Attempts to retrieve file in this order:
  # 1. Local cache (ext_tmp/projects/<instance>/)
  # 2. Download from server_url, and only from there
  #
  # @param project [String] Project path (e.g., "gnome/citemplates")
  # @param file [String] File path within project
  # @param ref [String] Git ref (branch/tag/commit) to fetch from
  # @param server_url [String] https:// URL of the GitLab instance
  #   (PredefinedVariables.server_url)
  # @return [String] File content
  # @raise [RuntimeError] If file cannot be fetched
  def fetch_project_file(project, file, ref:, server_url:)
    instance = parse_server_url(server_url)
    cache_path = project_file_cache_path(instance, project, file, ref)
    return File.read(cache_path) if File.exist?(cache_path)

    download_project_file(instance, project, file, ref)
  end

  # Fetch a component from a GitLab instance
  #
  # Components are CI/CD templates stored in GitLab projects (GitLab 16.0+)
  #
  # @param fqdn [String] GitLab instance FQDN (e.g., "gitlab.com")
  # @param project [String] Project path
  # @param file [String] Component file path
  # @param version [String] Component version/ref
  # @return [String] Component content
  # @raise [RuntimeError] If component cannot be fetched
  def fetch_component(fqdn, project, file, version)
    # Components are cached separately
    cache_path = component_cache_path(fqdn, project, file, version)
    if File.exist?(cache_path)
      return File.read(cache_path)
    end

    # Download component from the specific GitLab instance
    base_url = "https://#{fqdn}"
    url = "#{base_url}/#{project}/-/raw/#{version}/#{file}"

    content = download_file(url, "component: #{fqdn}/#{project}/#{file}@#{version}")

    # Validate content is not HTML
    if content.strip =~ /^<(!DOCTYPE|html|HTML)/i
      raise "Response appears to be HTML (likely authentication required or component not found)"
    end

    # Save to cache
    FileUtils.mkdir_p(File.dirname(cache_path))
    File.write(cache_path, content)

    content
  rescue StandardError => e
    raise "Failed to download component #{fqdn}/#{project}/#{file}@#{version}: #{e.message}"
  end

  private

  # The cache's top-level directories, one per kind of download.
  CACHE_KINDS = %w[templates projects components].freeze

  # Ensure cache directories exist
  def ensure_cache_directories
    CACHE_KINDS.each { |kind| FileUtils.mkdir_p(File.join(@cache_root, kind)) }
  end

  # The one place a path under the cache root is built; every read and
  # write of a cached file goes through it. Each part (host, project, ref
  # or version, file) comes from the config or the server, so each '/'
  # separated segment must be a plain name: not empty (also rules out an
  # absolute or '//' part), '.', '..', and no NUL or backslash. Then the
  # result must still lie under the root (negative-space assertion, in
  # case a segment rule is ever loosened).
  #
  # @param kind [String] one of CACHE_KINDS
  # @param parts [Array<String>] path parts, each may contain '/'
  # @return [String]
  # @raise [RuntimeError] a part that is no plain relative path
  def cache_path(kind, *parts)
    raise ArgumentError, "unknown cache kind #{kind.inspect}" unless CACHE_KINDS.include?(kind)

    segments = parts.flat_map { |part| part.to_s.split('/', -1) }
    bad = segments.find { |segment| segment.empty? || %w[. ..].include?(segment) || segment.match?(/[\0\\]/) }
    if bad || segments.empty?
      raise "Refusing cache path for #{parts.join(' ').inspect}: segment #{bad.inspect} " \
            "(empty, '.', '..', NUL or backslash) would not be a plain name under #{@cache_root}"
    end

    path = File.join(@cache_root, kind, *segments)
    root = File.expand_path(@cache_root) + File::SEPARATOR
    raise "Refusing cache path #{path.inspect}: outside #{root}" unless File.expand_path(path).start_with?(root)

    path
  end

  # Get cache path for a template
  #
  # @param template_name [String] Template name
  # @return [String] Full path to cached template
  def template_cache_path(template_name)
    cache_path('templates', template_name)
  end

  # The instance URL as a URI, https and a host required. Checked here, at
  # fetch time, not when CI_SERVER_URL is set: a --variables CI_SERVER_URL
  # that only feeds rules (say an http:// one) must not fail a pipeline
  # that never fetches a project file.
  #
  # @return [URI::HTTPS]
  def parse_server_url(server_url)
    uri = URI.parse(server_url.to_s)
    unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty? && uri.userinfo.nil? && uri.query.nil? &&
           uri.fragment.nil? && !uri.path.split('/').include?('..')
      raise "include:project needs an https:// GitLab instance URL without credentials, query, fragment or '..'; " \
            "CI_SERVER_URL is #{server_url.inspect}"
    end

    uri
  rescue URI::InvalidURIError => e
    raise "CI_SERVER_URL #{server_url.inspect} is not a URL: #{e.message}"
  end

  # Get cache path for a project file: per instance (the same project path
  # on two instances is two projects), then project, ref, file.
  #
  # @param instance [URI::HTTPS] parse_server_url
  # @return [String] Full path to cached file
  def project_file_cache_path(instance, project, file, ref)
    authority = instance.port == instance.default_port ? instance.host : "#{instance.host}:#{instance.port}"
    cache_path('projects', authority + instance.path.chomp('/'), project, ref, file)
  end

  # Get cache path for a component
  #
  # @param fqdn [String] GitLab instance FQDN
  # @param project [String] Project path
  # @param file [String] Component file
  # @param version [String] Component version
  # @return [String] Full path to cached component
  def component_cache_path(fqdn, project, file, version)
    cache_path('components', fqdn, project, version, file)
  end

  # Download a template from gitlab.com
  #
  # @param template_name [String] Template name
  # @return [String] Template content
  # @raise [RuntimeError] If download fails
  def download_template(template_name)
    cache_path = template_cache_path(template_name)
    url = "#{GITLAB_COM_URL}/#{GITLAB_REPO}/-/raw/#{DEFAULT_BRANCH}/lib/gitlab/ci/templates/#{template_name}"

    content = download_file(url, "template: #{template_name}")

    # Save to cache
    FileUtils.mkdir_p(File.dirname(cache_path))
    File.write(cache_path, content)

    content
  end

  # Download a project file from one GitLab instance
  #
  # @param instance [URI::HTTPS] parse_server_url
  # @return [String] File content
  # @raise [RuntimeError] If download fails; names the instance and how it
  #   was chosen
  def download_project_file(instance, project, file, ref)
    base_url = instance.to_s.chomp('/')
    url = "#{base_url}/#{project}/-/raw/#{ref}/#{file}"
    content = download_file(url, "project file: #{project}/#{file}@#{ref}")

    # Validate content is not HTML (fallback check for login redirects)
    if content.strip =~ /^<(!DOCTYPE|html|HTML)/i
      raise "Response appears to be HTML (likely authentication required)"
    end

    cache_path = project_file_cache_path(instance, project, file, ref)
    FileUtils.mkdir_p(File.dirname(cache_path))
    File.write(cache_path, content)

    content
  rescue StandardError => e
    raise "Failed to download project file #{project}/#{file}@#{ref} from GitLab instance #{base_url} " \
          "(--variables CI_SERVER_URL, else the origin remote's host, else gitlab.com): #{e.message}"
  end

  # Download a file via HTTPS
  #
  # @param url [String] URL to download
  # @param description [String] Description for error messages
  # @param max_redirects [Integer] Maximum number of redirects to follow
  # @return [String] File content
  # @raise [RuntimeError] If download fails
  def download_file(url, description, max_redirects: 5)
    redirect_count = 0
    current_url = url

    loop do
      uri = URI.parse(current_url)

      # Validate HTTPS
      unless uri.scheme == 'https'
        raise "Insecure URL for #{description}: #{current_url} (must use HTTPS)"
      end

      # Perform HTTP request with timeout
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        read_timeout: HTTP_TIMEOUT,
        open_timeout: HTTP_TIMEOUT,
        verify_mode: OpenSSL::SSL::VERIFY_PEER
      ) do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        http.request(request)
      end

      # Handle response
      case response
      when Net::HTTPSuccess
        # Validate Content-Type to catch HTML redirect pages
        content_type = response['content-type']
        if content_type && content_type.downcase.include?('text/html')
          raise "Received HTML response (likely authentication required). Content-Type: #{content_type}"
        end

        return response.body
      when Net::HTTPRedirection
        # Follow redirect
        redirect_count += 1
        if redirect_count > max_redirects
          raise "Too many redirects (>#{max_redirects}) downloading #{description} from #{url}"
        end

        # Get redirect location
        location = response['location']
        unless location
          raise "Redirect response missing Location header for #{description} from #{current_url}"
        end

        # Handle relative redirects
        current_url = if location.start_with?('http')
                        location
                      else
                        URI.join(current_url, location).to_s
                      end
      else
        raise "Failed to download #{description} from #{current_url}: HTTP #{response.code} #{response.message}"
      end
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise "Timeout downloading #{description} from #{url}: #{e.message}"
  rescue StandardError => e
    raise "Error downloading #{description} from #{url}: #{e.message}"
  end
end
