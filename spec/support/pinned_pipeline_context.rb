# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# The pipeline context specs run in, independent of the checkout.
#
# PredefinedVariables derives the ref (CI_COMMIT_BRANCH/TAG/REF_*), SHA and
# CI_DEFAULT_BRANCH from the git state of the project dir, and include/job
# rules read them (e.g. spec/fixtures/yaml/complex_pipeline.yml gates jobs
# on $CI_COMMIT_BRANCH == "main"). Unpinned, a spec that drives rules
# through the CLI or PipelineBuilder passes on main and fails on a feature
# branch, a detached HEAD or a GitLab CI checkout. Every such spec passes
# these. Same values as generate_output_references.sh's pinned_git_context.
#
# The ref is pinned with --ref, not with --variables: the ref kind decides
# which variables are SET (a branch pipeline has CI_COMMIT_BRANCH and no
# CI_COMMIT_TAG; an MR pipeline has neither), and --variables can only
# overlay a value, never unset one. refs/heads/ so no local tag named main
# can turn it into a tag pipeline. What is always set is pinned by value.
#
# Pinned first, so a spec's own --pipeline/--ref/--variables still win.
module PinnedPipelineContext
  REF = 'refs/heads/main'
  VARIABLES = {
    'CI_DEFAULT_BRANCH' => 'main',
    'CI_COMMIT_SHA' => '0000000000000000000000000000000000000000',
    'CI_COMMIT_SHORT_SHA' => '00000000'
  }.freeze
  PIPELINE_SOURCE = 'push'

  # For bin/gitlab_ci_cli invocations.
  CLI_ARGS = [
    '--pipeline', PIPELINE_SOURCE,
    '--ref', REF,
    *VARIABLES.flat_map { |key, value| ['--variables', "#{key}=#{value}"] }
  ].freeze

  # For in-process commands (LintCommand.execute, DagCommand.new, ...).
  def self.options
    { pipeline: PIPELINE_SOURCE, ref: REF, variables: VARIABLES.dup }
  end

  # For PipelineBuilder::Context.new in specs.
  def self.context(project_dir, variables: {})
    PipelineBuilder::Context.new(project_dir: project_dir, gitlab_dir: nil, pipeline_source: PIPELINE_SOURCE,
                                 ref: REF, variables: VARIABLES.merge(variables))
  end
end
