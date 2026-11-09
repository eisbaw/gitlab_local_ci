# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# Keyword tables of .gitlab-ci.yml, transcribed from the upstream reference
# (gitlab/ submodule, v19.5.3-ee). The single source for "is this top-level
# key a job?": every command, ExtendsResolver and MockServer ask here, so
# they cannot disagree about which keys are jobs.
module CiKeywords
  # Entry::Root::ALLOWED_KEYS (gitlab/lib/gitlab/ci/config/entry/root.rb).
  # A top-level key in this list is global configuration and never a job;
  # upstream marks these names reserved, so no job may use them.
  ROOT = %w[
    default include before_script image services
    after_script variables stages cache workflow
  ].freeze

  module_function

  # Upstream Entry::Jobs: a non-root key whose value is a Hash is a job
  # entry (hidden or visible). Non-Hash values are config errors upstream;
  # here they are skipped (lint parity is TASK-16).
  def job_entry?(key, value)
    !ROOT.include?(key.to_s) && value.is_a?(Hash)
  end

  # Upstream Entry::Hidden: a job whose name starts with '.' is a template,
  # never created as a job.
  def hidden?(name)
    name.to_s.start_with?('.')
  end
end
