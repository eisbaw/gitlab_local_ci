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
# - Project files from gitlab.com
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

  # Known GitLab instances to try for project includes
  KNOWN_GITLAB_INSTANCES = [
    'https://gitlab.com',
    'https://gitlab.gnome.org',
    'https://gitlab.freedesktop.org'
  ].freeze

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
    # Strategy 1: Check local gitlab submodule
    if gitlab_templates_path
      local_path = File.join(gitlab_templates_path, template_name)
      if File.exist?(local_path)
        return File.read(local_path)
      end
    end

    # Strategy 2: Check local cache
    cache_path = template_cache_path(template_name)
    if File.exist?(cache_path)
      return File.read(cache_path)
    end

    # Strategy 3: Download from gitlab.com
    download_template(template_name)
  end

  # Fetch a file from another GitLab project
  #
  # Attempts to retrieve file in this order:
  # 1. Local cache (ext_tmp/projects/)
  # 2. Download from gitlab.com
  #
  # @param project [String] Project path (e.g., "gnome/citemplates")
  # @param file [String] File path within project
  # @param ref [String] Git ref (branch/tag/commit) to fetch from
  # @return [String] File content
  # @raise [RuntimeError] If file cannot be fetched
  def fetch_project_file(project, file, ref: 'master')
    # Strategy 1: Check local cache
    cache_path = project_file_cache_path(project, file, ref)
    if File.exist?(cache_path)
      return File.read(cache_path)
    end

    # Strategy 2: Download from gitlab.com
    download_project_file(project, file, ref)
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

  # Ensure cache directories exist
  def ensure_cache_directories
    FileUtils.mkdir_p(File.join(@cache_root, 'templates'))
    FileUtils.mkdir_p(File.join(@cache_root, 'projects'))
    FileUtils.mkdir_p(File.join(@cache_root, 'components'))
  end

  # Get cache path for a template
  #
  # @param template_name [String] Template name
  # @return [String] Full path to cached template
  def template_cache_path(template_name)
    File.join(@cache_root, 'templates', template_name)
  end

  # Get cache path for a project file
  #
  # @param project [String] Project path
  # @param file [String] File path
  # @param ref [String] Git ref
  # @return [String] Full path to cached file
  def project_file_cache_path(project, file, ref)
    # Use ref in path to cache different versions
    File.join(@cache_root, 'projects', project, ref, file)
  end

  # Get cache path for a component
  #
  # @param fqdn [String] GitLab instance FQDN
  # @param project [String] Project path
  # @param file [String] Component file
  # @param version [String] Component version
  # @return [String] Full path to cached component
  def component_cache_path(fqdn, project, file, version)
    File.join(@cache_root, 'components', fqdn, project, version, file)
  end

  # Download a template from gitlab.com
  #
  # @param template_name [String] Template name
  # @return [String] Template content
  # @raise [RuntimeError] If download fails
  def download_template(template_name)
    url = "#{GITLAB_COM_URL}/#{GITLAB_REPO}/-/raw/#{DEFAULT_BRANCH}/lib/gitlab/ci/templates/#{template_name}"

    content = download_file(url, "template: #{template_name}")

    # Save to cache
    cache_path = template_cache_path(template_name)
    FileUtils.mkdir_p(File.dirname(cache_path))
    File.write(cache_path, content)

    content
  end

  # Download a project file from GitLab instances
  #
  # Tries multiple known GitLab instances until one succeeds
  #
  # @param project [String] Project path
  # @param file [String] File path
  # @param ref [String] Git ref
  # @return [String] File content
  # @raise [RuntimeError] If download fails from all instances
  def download_project_file(project, file, ref)
    errors = []

    # Try each known GitLab instance
    KNOWN_GITLAB_INSTANCES.each do |base_url|
      begin
        url = "#{base_url}/#{project}/-/raw/#{ref}/#{file}"
        content = download_file(url, "project file: #{project}/#{file}@#{ref}")

        # Validate content is not HTML (fallback check for login redirects)
        # Check both lowercase and uppercase HTML tags
        if content.strip =~ /^<(!DOCTYPE|html|HTML)/i
          raise "Response appears to be HTML (likely authentication required)"
        end

        # Save to cache
        cache_path = project_file_cache_path(project, file, ref)
        FileUtils.mkdir_p(File.dirname(cache_path))
        File.write(cache_path, content)

        return content
      rescue StandardError => e
        errors << "#{base_url}: #{e.message}"
        # Continue to next instance
      end
    end

    # All instances failed
    raise "Failed to download project file #{project}/#{file}@#{ref} from any known GitLab instance. Tried:\n" +
          errors.map { |e| "  - #{e}" }.join("\n")
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
