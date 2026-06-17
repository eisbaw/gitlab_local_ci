# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'open3'

# PredefinedVariables — builds the `CI_*` defaults that GitLab injects
# before any rule evaluation runs.
#
# Mirrors a representative subset of:
#   https://docs.gitlab.com/ee/ci/variables/predefined_variables.html
#
# All shell-outs are defensive: any failure (no git, detached HEAD, no
# tag, missing remote, etc.) is swallowed and the variable becomes the
# empty string. This matches how a brand-new repo behaves on a runner.
#
# NOT implemented (out of scope for local lint):
#   - CI_API_*, CI_REGISTRY_*, CI_ENVIRONMENT_*, CI_JOB_TOKEN, etc.
#   - Real CI_MERGE_REQUEST_* (we synthesize empty strings as a marker so
#     rules can test for the merge-request pipeline source).
module PredefinedVariables
  module_function

  # Build the predefined CI_* variable table.
  #
  # @param project_dir [String] Absolute path to project root.
  # @param pipeline_source [String] One of push|merge_request|schedule|web|manual.
  # @param job_name [String, nil] Job name if evaluating per-job rules.
  # @param job_stage [String, nil] Stage if evaluating per-job rules.
  # @return [Hash<String,String>] Variable map (string keys, string values).
  def build(project_dir:, pipeline_source: 'push', job_name: nil, job_stage: nil)
    vars = {}

    project_dir = File.expand_path(project_dir || Dir.pwd)
    vars['CI_PROJECT_DIR']  = project_dir
    vars['CI_PROJECT_NAME'] = File.basename(project_dir)
    # GitLab's CI_PROJECT_PATH is `<group>/<name>` — we have no group
    # locally, so fall back to just the name (matches what runners on a
    # standalone repo see).
    vars['CI_PROJECT_PATH'] = vars['CI_PROJECT_NAME']

    vars['CI_PIPELINE_SOURCE'] = pipeline_source.to_s

    branch = git_run(['rev-parse', '--abbrev-ref', 'HEAD'], cwd: project_dir)
    branch = '' if branch == 'HEAD' # detached
    vars['CI_COMMIT_BRANCH'] = branch

    tag = git_run(['describe', '--exact-match', '--tags', 'HEAD'], cwd: project_dir)
    vars['CI_COMMIT_TAG'] = tag

    ref_name = tag.empty? ? branch : tag
    vars['CI_COMMIT_REF_NAME'] = ref_name
    vars['CI_COMMIT_REF_SLUG'] = slugify(ref_name)

    sha = git_run(['rev-parse', 'HEAD'], cwd: project_dir)
    vars['CI_COMMIT_SHA']       = sha
    vars['CI_COMMIT_SHORT_SHA'] = sha[0, 8]

    default_branch = git_run(['symbolic-ref', 'refs/remotes/origin/HEAD'], cwd: project_dir)
    default_branch = default_branch.sub(%r{^.*/}, '')
    default_branch = 'main' if default_branch.empty?
    vars['CI_DEFAULT_BRANCH'] = default_branch

    # Per-job vars only meaningful at job-rule eval time.
    vars['CI_JOB_NAME']  = job_name.to_s  if job_name
    vars['CI_JOB_STAGE'] = job_stage.to_s if job_stage

    # Synthesize an empty CI_MERGE_REQUEST_IID marker only when the
    # caller said this is a merge_request pipeline — gives rules a
    # variable to test for, without inventing fake numeric IDs.
    if pipeline_source.to_s == 'merge_request'
      vars['CI_MERGE_REQUEST_IID']             = ''
      vars['CI_MERGE_REQUEST_SOURCE_BRANCH_NAME'] = branch
      vars['CI_MERGE_REQUEST_TARGET_BRANCH_NAME'] = default_branch
    end

    vars
  end

  # Lowercase, non-alnum -> "-", truncate to 63 chars.
  # Mirrors GitLab's CI_COMMIT_REF_SLUG transformation.
  def slugify(ref)
    return '' if ref.nil? || ref.empty?
    slug = ref.downcase.gsub(/[^a-z0-9]/, '-')
    # GitLab also strips leading/trailing dashes after truncation.
    slug = slug[0, 63]
    slug.sub(/\A-+/, '').sub(/-+\z/, '')
  end

  # Run a git command, returning trimmed stdout on success, '' on any
  # failure (non-git dir, command missing, non-zero exit, etc.).
  def git_run(args, cwd:)
    stdout, _stderr, status = Open3.capture3('git', '-C', cwd, *args)
    return '' unless status.success?
    stdout.strip
  rescue StandardError
    ''
  end
end
