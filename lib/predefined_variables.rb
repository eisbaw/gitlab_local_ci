# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'open3'

# PredefinedVariables: the CI_* variables GitLab defines before rules run
# (doc/ci/variables/predefined_variables.md, "Pre-pipeline" and "Pipeline"
# availability), for one pipeline.
#
# Two layers:
#   read_git            I/O only: facts about the checkout, nil when unknown
#   everything else     pure: facts + pipeline source + ref -> variables
#
# A variable that does not apply to this pipeline, or whose value cannot be
# known locally, is UNSET, never ''. Rules tell the two apart
# (`$CI_COMMIT_TAG == null`), and upstream only appends what applies
# (Gitlab::Ci::Variables::Builder::Pipeline#predefined_variables). The only
# '' values are upstream's own: the MR SHAs below, and the message or
# description of a blank or one-line commit message.
#
# Pipeline variables (upstream builder/pipeline.rb, project.rb):
#   always    CI, GITLAB_CI, CI_PIPELINE_SOURCE, CI_PROJECT_DIR,
#             CI_PROJECT_NAME, CI_PROJECT_PATH, CI_PROJECT_PATH_SLUG,
#             CI_DEFAULT_BRANCH, CI_DEFAULT_BRANCH_SLUG
#   remote    CI_PROJECT_NAMESPACE(_SLUG), CI_PROJECT_ROOT_NAMESPACE(_SLUG):
#             only when `origin` is a host URL with a namespace
#   commit    CI_COMMIT_SHA, CI_COMMIT_SHORT_SHA, CI_COMMIT_MESSAGE,
#             CI_COMMIT_MESSAGE_IS_TRUNCATED, CI_COMMIT_TITLE,
#             CI_COMMIT_DESCRIPTION, CI_COMMIT_TIMESTAMP, CI_COMMIT_AUTHOR:
#             HEAD of the checkout (the config is read from the working
#             tree, so HEAD is the commit being simulated, whatever --ref)
#   ref       CI_COMMIT_REF_NAME, CI_COMMIT_REF_SLUG; CI_COMMIT_BRANCH only
#             in a branch pipeline (HasRef#branch?: not tag, not MR);
#             CI_COMMIT_TAG only in a tag pipeline
#   MR        merge_request_event only: CI_MERGE_REQUEST_IID (placeholder,
#             see MERGE_REQUEST_IID_PLACEHOLDER), _SOURCE_BRANCH_NAME (the
#             ref), _TARGET_BRANCH_NAME (the default branch), _EVENT_TYPE
#             'detached', _SOURCE_BRANCH_SHA and _TARGET_BRANCH_SHA ''
#             (upstream sets them empty outside merged-results pipelines),
#             _PROJECT_PATH and _SOURCE_PROJECT_PATH (same-project MR)
# Job variables (Builder#predefined_variables_from_job_attr), job_variables:
#   CI_JOB_NAME, CI_JOB_NAME_SLUG, CI_JOB_GROUP_NAME, CI_JOB_STAGE,
#   CI_JOB_MANUAL (when: manual/delayed only)
#
# Deliberately omitted (unknowable locally; pass --variables to simulate):
#   CI_PROJECT_ID/TITLE/DESCRIPTION/TOPICS/URL/VISIBILITY/..., CI_SERVER_*,
#   CI_API_*, CI_REGISTRY*, CI_PAGES_*, CI_DEPENDENCY_PROXY_*, GITLAB_FEATURES,
#   GITLAB_USER_*, CI_PIPELINE_IID/NAME/SCHEDULE_DESCRIPTION,
#   CI_COMMIT_REF_PROTECTED, CI_COMMIT_BEFORE_SHA, CI_COMMIT_USER_LOGIN,
#   CI_COMMIT_TAG_MESSAGE, CI_COMMIT_DEFAULT_BRANCH_BASE_SHA,
#   CI_CONFIG_PATH, CI_OPEN_MERGE_REQUESTS (set it to simulate a branch
#   with an open MR), CI_MERGE_REQUEST_ID/REF_PATH/TITLE/LABELS/... ,
#   CI_DEPLOY_FREEZE, CI_KUBERNETES_ACTIVE, CI_ENVIRONMENT_* (TASK-11),
#   CI_NODE_INDEX/CI_NODE_TOTAL (parallel expansion, TASK-18), and every
#   "Job-only" variable (the runner sets those).
module PredefinedVariables
  # Upstream Enums::Ci::Pipeline.sources, minus `unknown`.
  SOURCES = %w[
    push web trigger schedule api external pipeline chat webide
    merge_request_event external_pull_request_event parent_pipeline
    ondemand_dast_scan ondemand_dast_validation security_orchestration_policy
    container_registry_push duo_workflow pipeline_execution_policy_schedule
    dependency_management_security_update
  ].freeze

  # Names this tool accepted before it used upstream's. `manual` was never
  # an upstream source; a pipeline started with "Run pipeline" is `web`.
  SOURCE_ALIASES = { 'merge_request' => 'merge_request_event', 'manual' => 'web' }.freeze

  MERGE_REQUEST_SOURCE = 'merge_request_event'

  # An MR pipeline always has an IID upstream, so `if: $CI_MERGE_REQUEST_IID`
  # must be true; the real number cannot be known locally. Override with
  # --variables CI_MERGE_REQUEST_IID=<n>.
  MERGE_REQUEST_IID_PLACEHOLDER = '1'

  # Neither origin/HEAD nor --variables CI_DEFAULT_BRANCH says otherwise.
  DEFAULT_BRANCH_FALLBACK = 'main'

  # Upstream Builder::Pipeline::MAX_COMMIT_MESSAGE_SIZE_IN_BYTES default.
  COMMIT_MESSAGE_BYTES_MAX = 100_000

  # Upstream Commit#no_commit_message.
  NO_COMMIT_MESSAGE = 'No commit message'

  # Upstream Gitlab::Utils.slugify truncation.
  SLUG_LENGTH_MAX = 63

  # Upstream Gitlab::Utils::Job::PARALLEL_VARIANT_REGEX: the " 1/3" or
  # ": [aws, x]" suffix of a parallel job name.
  PARALLEL_VARIANT_REGEX = %r{([\b\s:]+((\[.*\])|(\d+[\s:/\\]+\d+))){1,3}\s*\z}

  # Upstream Ci::Processable::ACTIONABLE_WHEN.
  ACTIONABLE_WHEN = %w[manual delayed].freeze

  # The ref a pipeline runs for. kind is :branch or :tag.
  Ref = Struct.new(:kind, :name, keyword_init: true)

  # --ref cannot be resolved (operating error, reported to the user).
  RefError = Class.new(StandardError)

  module_function

  # Canonical upstream source name for a CLI --pipeline value.
  #
  # @raise [ArgumentError] not an upstream source or alias
  def canonical_source(name)
    source = SOURCE_ALIASES.fetch(name.to_s, name.to_s)
    raise ArgumentError, "unknown pipeline source #{name.inspect}" unless SOURCES.include?(source)

    source
  end

  # Pipeline variables for this checkout.
  #
  # @param project_dir [String] repository root
  # @param pipeline_source [String] upstream source name (canonical_source)
  # @param ref [String, nil] --ref: nil or 'HEAD' for the checkout's
  #   branch/tag, NAME, refs/heads/NAME or refs/tags/NAME
  # @return [Hash{String=>String}]
  # @raise [RefError]
  def build(project_dir:, pipeline_source: 'push', ref: nil)
    project_dir = File.expand_path(project_dir)
    git = read_git(project_dir, requested_ref_name(ref))
    pipeline_variables(project_dir: project_dir, source: pipeline_source,
                       ref: resolve_ref(ref, git, pipeline_source), git: git)
  end

  # @param git [Hash] read_git facts
  # @param ref [Ref, nil] nil: the ref is unknown (detached HEAD, no git)
  # @return [Hash{String=>String}]
  def pipeline_variables(project_dir:, source:, ref:, git:)
    raise ArgumentError, "not an upstream pipeline source: #{source.inspect}" unless SOURCES.include?(source)

    merge_request = source == MERGE_REQUEST_SOURCE
    raise ArgumentError, 'a merge request pipeline needs a branch ref' if merge_request && ref&.kind != :branch

    default_branch = git[:default_branch] || DEFAULT_BRANCH_FALLBACK
    project_path = project_path_from_remote(git[:remote_url]) || File.basename(project_dir)

    vars = {
      'CI' => 'true',
      'GITLAB_CI' => 'true',
      'CI_PIPELINE_SOURCE' => source,
      'CI_PROJECT_DIR' => project_dir,
      'CI_DEFAULT_BRANCH' => default_branch,
      'CI_DEFAULT_BRANCH_SLUG' => slugify(default_branch)
    }
    vars.merge!(project_variables(project_path))
    vars.merge!(commit_variables(git[:sha], git[:commit_message], git[:commit]))
    vars.merge!(ref_variables(ref, merge_request: merge_request)) if ref
    vars.merge!(merge_request_variables(ref, default_branch, project_path)) if merge_request
    vars
  end

  # Upstream Project#predefined_project_variables, the path-derived ones.
  # project_path is "namespace/.../name", or just "name" when the namespace
  # is unknown (then the namespace variables are unset).
  def project_variables(project_path)
    *namespace, name = project_path.split('/')
    vars = {
      'CI_PROJECT_NAME' => name,
      'CI_PROJECT_PATH' => project_path,
      'CI_PROJECT_PATH_SLUG' => slugify(project_path)
    }
    return vars if namespace.empty?

    vars.merge(
      'CI_PROJECT_NAMESPACE' => namespace.join('/'),
      'CI_PROJECT_NAMESPACE_SLUG' => slugify(namespace.join('/')),
      'CI_PROJECT_ROOT_NAMESPACE' => namespace.first,
      'CI_PROJECT_ROOT_NAMESPACE_SLUG' => slugify(namespace.first)
    )
  end

  # Upstream predefined_commit_variables (commit part). Message, title and
  # description as Commit#full_title/#description (a one-line message has
  # description '', as upstream; a blank one has upstream's placeholder);
  # truncation in bytes.
  #
  # @param sha [String, nil]
  # @param message [String, nil] raw commit message
  # @param commit [Hash, nil] { epoch:, author_name:, author_email: }
  def commit_variables(sha, message, commit)
    return {} if sha.nil?

    vars = { 'CI_COMMIT_SHA' => sha, 'CI_COMMIT_SHORT_SHA' => sha[0, 8] }
    return vars if message.nil? || commit.nil?

    truncated = message.bytesize > COMMIT_MESSAGE_BYTES_MAX
    if message.strip.empty?
      title = description = NO_COMMIT_MESSAGE
    else
      title = message.split(/[\r\n]/, 2).first
      description = title.length >= 100 ? message : message.split("\n", 2)[1].to_s.chomp
    end
    vars.merge(
      'CI_COMMIT_MESSAGE' => truncate_bytes(message, truncated),
      'CI_COMMIT_MESSAGE_IS_TRUNCATED' => truncated.to_s,
      'CI_COMMIT_TITLE' => truncate_bytes(title, truncated),
      'CI_COMMIT_DESCRIPTION' => truncate_bytes(description, truncated),
      'CI_COMMIT_TIMESTAMP' => Time.at(commit.fetch(:epoch)).utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
      'CI_COMMIT_AUTHOR' => "#{commit.fetch(:author_name)} <#{commit.fetch(:author_email)}>"
    )
  end

  def truncate_bytes(text, truncated)
    truncated ? text.byteslice(0, COMMIT_MESSAGE_BYTES_MAX).scrub('') : text
  end

  # REF_NAME is the source branch in an MR pipeline (Pipeline#source_ref),
  # which is the ref here. BRANCH only for HasRef#branch?, TAG only for a
  # tag pipeline.
  def ref_variables(ref, merge_request:)
    vars = { 'CI_COMMIT_REF_NAME' => ref.name, 'CI_COMMIT_REF_SLUG' => slugify(ref.name) }
    vars['CI_COMMIT_BRANCH'] = ref.name if ref.kind == :branch && !merge_request
    vars['CI_COMMIT_TAG'] = ref.name if ref.kind == :tag
    vars
  end

  # Upstream predefined_merge_request_variables + MergeRequest
  # #predefined_variables, the ones knowable locally (module comment).
  def merge_request_variables(ref, default_branch, project_path)
    {
      'CI_MERGE_REQUEST_IID' => MERGE_REQUEST_IID_PLACEHOLDER,
      'CI_MERGE_REQUEST_EVENT_TYPE' => 'detached',
      'CI_MERGE_REQUEST_SOURCE_BRANCH_NAME' => ref.name,
      'CI_MERGE_REQUEST_SOURCE_BRANCH_SHA' => '',
      'CI_MERGE_REQUEST_TARGET_BRANCH_NAME' => default_branch,
      'CI_MERGE_REQUEST_TARGET_BRANCH_SHA' => '',
      'CI_MERGE_REQUEST_PROJECT_PATH' => project_path,
      'CI_MERGE_REQUEST_SOURCE_PROJECT_PATH' => project_path
    }
  end

  # Variables of one job that its rules see (upstream
  # Builder#predefined_variables_from_job_attr, the seed-time subset).
  #
  # @param name [String] job name
  # @param stage [String] the job's stage (default already applied)
  # @param when_value [String, nil] the job's own `when:`
  def job_variables(name:, stage:, when_value:)
    vars = {
      'CI_JOB_NAME' => name,
      'CI_JOB_NAME_SLUG' => slugify(name),
      'CI_JOB_GROUP_NAME' => group_name(name),
      'CI_JOB_STAGE' => stage
    }
    vars['CI_JOB_MANUAL'] = 'true' if ACTIONABLE_WHEN.include?(when_value.to_s)
    vars
  end

  # Upstream Gitlab::Utils::Job.group_name.
  def group_name(job_name)
    job_name.to_s.sub(PARALLEL_VARIANT_REGEX, '').strip
  end

  # Upstream Gitlab::Utils.slugify: lowercase, every non-alphanumeric to
  # '-', at most 63 chars, no leading/trailing '-'.
  def slugify(text)
    return '' if text.nil? || text.empty?

    text.downcase.gsub(/[^a-z0-9]/, '-')[0, SLUG_LENGTH_MAX].gsub(/\A-+|-+\z/, '')
  end

  # "namespace/.../name" from a GitLab remote URL, or nil when the URL has
  # no host or no namespace (e.g. a local path remote).
  #   git@host:group/sub/name.git          -> group/sub/name
  #   https://user:pw@host/group/name.git  -> group/name
  #   ssh://git@host:2222/group/name       -> group/name
  def project_path_from_remote(url)
    return nil if url.nil? || url.empty?

    path =
      if (match = url.match(%r{\A[a-z][a-z0-9+.-]*://[^/]+/(?<path>.+)\z}i))
        match[:path]
      elsif (match = url.match(%r{\A(?:[^@/]+@)?[^:/]+:(?<path>[^/].*)\z}))
        match[:path]
      end
    return nil if path.nil?

    path = path.delete_suffix('/').delete_suffix('.git')
    path.include?('/') && !path.split('/').any?(&:empty?) ? path : nil
  end

  # The ref name --ref asks about, without refs/heads/ or refs/tags/, or nil
  # for the checkout's own ref.
  def requested_ref_name(ref)
    return nil if ref.nil? || ref == 'HEAD'

    ref.delete_prefix('refs/heads/').delete_prefix('refs/tags/')
  end

  # Which ref this pipeline is for.
  #
  # @param ref [String, nil] --ref as given
  # @param git [Hash] read_git facts
  # @return [Ref, nil] nil when unknown (detached HEAD at no single tag, or
  #   no git): ref variables stay unset
  # @raise [RefError] ambiguous name, or an MR pipeline without a branch
  def resolve_ref(ref, git, source)
    resolved =
      if ref.nil? || ref == 'HEAD'
        if git[:head_branch] then Ref.new(kind: :branch, name: git[:head_branch])
        elsif git[:head_tag] then Ref.new(kind: :tag, name: git[:head_tag])
        end
      elsif ref.start_with?('refs/heads/') then Ref.new(kind: :branch, name: requested_ref_name(ref))
      elsif ref.start_with?('refs/tags/') then Ref.new(kind: :tag, name: requested_ref_name(ref))
      else
        # Upstream Chain::Validate::Repository rejects a name that is both.
        raise RefError, "Ref is ambiguous: #{ref} is a branch and a tag; pass refs/heads/#{ref} or refs/tags/#{ref}" if git[:ref_is_tag] && git[:ref_is_branch]

        Ref.new(kind: git[:ref_is_tag] ? :tag : :branch, name: ref)
      end
    return resolved unless source == MERGE_REQUEST_SOURCE && resolved&.kind != :branch

    raise RefError, 'a merge_request_event pipeline runs for a source branch: ' +
                    (resolved ? "--ref #{resolved.name} is a tag" : 'check out a branch or pass --ref BRANCH')
  end

  # Facts about the checkout at project_dir, each nil when unknown (not a
  # git repo, no commit, detached HEAD, no origin, ...). The only I/O here.
  #
  # @param ref_name [String, nil] also report whether this name is a local
  #   tag (:ref_is_tag) and a branch (:ref_is_branch, local or origin)
  # @return [Hash]
  def read_git(project_dir, ref_name)
    return {} unless git(project_dir, 'rev-parse', '--is-inside-work-tree') == 'true'

    head_tags = git(project_dir, 'tag', '--points-at', 'HEAD').to_s.split("\n")
    sha = git(project_dir, 'rev-parse', '--verify', '--quiet', 'HEAD^{commit}')
    facts = {
      head_branch: git(project_dir, 'symbolic-ref', '--quiet', '--short', 'HEAD'),
      head_tag: head_tags.size == 1 ? head_tags.first : nil,
      sha: sha,
      default_branch: git(project_dir, 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')&.delete_prefix('origin/'),
      remote_url: git(project_dir, 'remote', 'get-url', 'origin')
    }
    facts.merge!(read_commit(project_dir)) if sha
    if ref_name
      facts[:ref_is_tag] = ref_exists?(project_dir, "refs/tags/#{ref_name}")
      facts[:ref_is_branch] = ref_exists?(project_dir, "refs/heads/#{ref_name}") ||
                              ref_exists?(project_dir, "refs/remotes/origin/#{ref_name}")
    end
    facts
  end

  # HEAD's raw message (git cat-file: exactly what was committed) and
  # committer time / author.
  def read_commit(project_dir)
    raw = git(project_dir, 'cat-file', 'commit', 'HEAD', strip: false)
    meta = git(project_dir, 'log', '-1', '--format=%ct%x00%an%x00%ae', 'HEAD')
    return {} if raw.nil? || meta.nil?

    epoch, author_name, author_email = meta.split("\0", 3)
    {
      commit_message: raw.split("\n\n", 2)[1].to_s,
      commit: { epoch: Integer(epoch, 10), author_name: author_name, author_email: author_email }
    }
  end

  def ref_exists?(project_dir, full_ref)
    !git(project_dir, 'show-ref', '--verify', '--quiet', full_ref).nil?
  end

  # stdout of `git -C project_dir args`, nil on a non-zero exit (that is
  # the answer: no such ref, not a repo, ...) or when git is not installed.
  def git(project_dir, *args, strip: true)
    stdout, _stderr, status = Open3.capture3('git', '-C', project_dir, *args)
    return nil unless status.success?

    strip ? stdout.strip : stdout
  rescue Errno::ENOENT
    nil
  end
end
