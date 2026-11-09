# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'simplecov'

# Coverage settings shared by the rspec process (spec_helper.rb) and every
# bin/gitlab_ci_cli subprocess the integration specs spawn
# (simplecov_cli_subprocess.rb). Both sides must measure the same way, or
# their results cannot be merged: same root, filters and branch coverage.
module SimpleCovConfig
  # Explicit, because SimpleCov defaults root to Dir.pwd and some specs run
  # the CLI with chdir: into a temp dir.
  ROOT = File.expand_path('..', __dir__)

  # Each CLI subprocess stores its result in SUBPROCESS_DIR/<pid>/; the rspec
  # process merges them once at exit. One shared resultset instead would be
  # re-read and re-written by every subprocess (~130 per run): quadratic I/O.
  SUBPROCESS_DIR = File.join(ROOT, 'coverage', 'cli')

  # Stale data is cleared at suite start (spec_helper.rb), so the merge
  # window only has to outlast one suite run. SimpleCov's default (600 s)
  # would silently drop subprocess results from a slow run.
  MERGE_TIMEOUT_SECONDS = 3600

  def self.apply_common
    SimpleCov.root(ROOT)
    SimpleCov.add_filter('/spec/')
    SimpleCov.add_filter('/gitlab/')
    SimpleCov.enable_coverage(:branch)
    SimpleCov.merge_timeout(MERGE_TIMEOUT_SECONDS)
  end
end
