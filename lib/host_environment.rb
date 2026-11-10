# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# Which of this host's environment variables a job started by `run` or an
# `export-just` recipe sees, under `--pass-env MODE` (TASK-56).
#
# Upstream, a shell executor's job inherits the runner process's
# environment, while the docker executor starts from a clean one. Here the
# default isolates: a run on a laptop, or inside a real CI job, must not
# silently pick up the host's CI_*/GITLAB_* values (CI_JOB_ID,
# CI_COMMIT_TAG, ...) where the simulated pipeline leaves them unset or
# sets its own. The job's GitLab variables (JobEnvironment) always go on
# top, so a same-named host variable never wins.
#
# Mode, as parsed by .parse:
#   []            `none` (default): BASE only
#   ['A', 'B']    BASE plus A and B
#   :all          the whole host environment (the behaviour before TASK-56)
#
# Pure: the host environment is passed in.
module HostEnvironment
  # The host variables every job gets: what a shell and the usual tools
  # need to work at all, nothing that says anything about a pipeline.
  # An entry ending in '*' is a name prefix.
  BASE = [
    'PATH',    # finding bash, coreutils and every tool a script calls
    'HOME',    # ~, dotfiles, tool caches (git, ssh, npm, ...)
    'USER',    # who runs it; some tools refuse to run without it
    'LOGNAME', # USER's POSIX twin, read by e.g. getlogin fallbacks
    'SHELL',   # tools that spawn "the user's shell"
    'LANG',    # locale: without it tools fall back to C/ASCII
    'LC_*',    # per-category locale overrides of LANG
    'TERM',    # tput, colours, curses; the job writes to this terminal
    'TZ',      # date and log timestamps in the user's zone
    'TMPDIR'   # where mktemp and friends write (per-user on some hosts)
  ].freeze

  # A name that may be passed: a POSIX shell identifier. Also what keeps
  # a name safe to write unquoted into a generated recipe.
  NAME_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  module_function

  # @param text [String] the --pass-env value: none, all, or NAME[,NAME...]
  # @return [Array<String>, :all] mode (module comment)
  # @raise [ArgumentError] an empty or invalid name, or none/all in a list
  def parse(text)
    return [] if text == 'none'
    return :all if text == 'all'

    names = text.split(',', -1)
    names = [''] if names.empty? # '' itself: one empty name, not an empty list
    names.each do |name|
      if %w[none all].include?(name)
        raise ArgumentError, "--pass-env: '#{name}' is a mode of its own, not a name to list with others: #{text}"
      end
      next if NAME_PATTERN.match?(name)

      raise ArgumentError, "--pass-env: invalid variable name #{name.inspect} in #{text.inspect}: " \
                           'expected none, all, or names like AWS_PROFILE,SSH_AUTH_SOCK ([A-Za-z_][A-Za-z0-9_]*)'
    end
    names.uniq.freeze
  end

  # The host variables a job gets under `mode`, before its own variables.
  #
  # @param host [Hash{String => String}] e.g. ENV.to_h
  # @param mode [Array<String>, :all]
  # @return [Hash{String => String}]
  def select(host, mode)
    return host.dup if mode == :all

    names = passed_names(mode)
    host.select { |name, _| names.any? { |entry| matches?(entry, name) } }
  end

  # BASE plus the listed names, BASE first, each once.
  #
  # @param mode [Array<String>] not :all (that passes everything)
  # @return [Array<String>] names and 'PREFIX*' entries
  def passed_names(mode)
    raise ArgumentError, "passed_names: mode must be a list of names, got #{mode.inspect}" unless mode.is_a?(Array)

    bad = mode.find { |name| !NAME_PATTERN.match?(name) }
    raise ArgumentError, "passed_names: invalid variable name #{bad.inspect}" if bad

    (BASE + mode).uniq
  end

  def matches?(entry, name)
    entry.end_with?('*') ? name.start_with?(entry.delete_suffix('*')) : name == entry
  end
end
