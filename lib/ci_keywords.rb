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

  # Keys a job entry may have: the union of upstream
  #   Entry::Job::ALLOWED_KEYS        (gitlab/lib/gitlab/ci/config/entry/job.rb)
  #   EE::...::Job::EE_ALLOWED_KEYS   (gitlab/ee/lib/ee/gitlab/ci/config/entry/job.rb)
  #   Entry::Bridge::ALLOWED_KEYS     (trigger jobs, .../entry/bridge.rb)
  #   Entry::Processable::PROCESSABLE_ALLOWED_KEYS (.../entry/processable.rb)
  # Upstream checks a Job against Job + Processable and a Bridge (has
  # trigger:) against Bridge + Processable; this list does not tell the two
  # apart (e.g. it accepts trigger: next to script:). Per-type checks: TASK-16.
  JOB = %w[
    tags script image services start_in artifacts cache dependencies
    before_script after_script hooks coverage retry parallel timeout inputs
    release id_tokens publish pages manual_confirmation run
    dast_configuration identity secrets
    trigger
    extends stage only except rules variables inherit allow_failure when
    needs resource_group environment interruptible
  ].uniq.freeze

  # Entry::Default::ALLOWED_KEYS (gitlab/lib/gitlab/ci/config/entry/default.rb):
  # the keys `default:` may set. Entry::Job declares each of them
  # `inherit: true`, so a job gets every one it does not set itself.
  DEFAULT = %w[
    before_script after_script hooks cache image services
    interruptible timeout retry tags artifacts id_tokens
  ].freeze

  # The Entry::Default entries declared `inherit: true`: the deprecated
  # top-level globals that act as `default:` keys (Entry::Root reserves
  # them; Default#overwrite_entry takes them when default: lacks them).
  LEGACY_DEFAULT = %w[before_script after_script cache image services].freeze

  # The only Processable entry declared `inherit: true`. A trigger job
  # (Entry::Bridge) declares none of Job's, so it inherits just this.
  BRIDGE_DEFAULT = %w[interruptible].freeze

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
