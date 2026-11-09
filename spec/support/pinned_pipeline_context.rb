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
# PredefinedVariables derives CI_COMMIT_* and CI_DEFAULT_BRANCH from the git
# state of the project dir, and include/job rules read them (e.g.
# spec/fixtures/yaml/complex_pipeline.yml gates jobs on
# $CI_COMMIT_BRANCH == "main"). Unpinned, a spec that drives rules through
# the CLI or PipelineBuilder passes on main and fails on a feature branch,
# a detached HEAD or a GitLab CI checkout. Every such spec passes these;
# CLI --variables overlay the git-derived values. Same values as
# generate_output_references.sh's pinned_git_context.
#
# Pinned first, so a spec's own --pipeline/--variables still win.
module PinnedPipelineContext
  VARIABLES = {
    'CI_COMMIT_BRANCH' => 'main',
    'CI_COMMIT_REF_NAME' => 'main',
    'CI_COMMIT_REF_SLUG' => 'main',
    'CI_COMMIT_TAG' => '',
    'CI_DEFAULT_BRANCH' => 'main',
    'CI_COMMIT_SHA' => '0000000000000000000000000000000000000000',
    'CI_COMMIT_SHORT_SHA' => '00000000'
  }.freeze
  PIPELINE_SOURCE = 'push'

  # For bin/gitlab_ci_cli invocations.
  CLI_ARGS = [
    '--pipeline', PIPELINE_SOURCE,
    *VARIABLES.flat_map { |key, value| ['--variables', "#{key}=#{value}"] }
  ].freeze

  # For in-process commands (LintCommand.execute, DagCommand.new, ...).
  def self.options
    { pipeline: PIPELINE_SOURCE, variables: VARIABLES.dup }
  end
end
