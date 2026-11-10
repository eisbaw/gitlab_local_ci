# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
require 'spec_helper'
require 'open3'

# The argument contract of bin/gitlab_ci_cli as a user sees it: a bad
# invocation exits 1 (EXIT_INVALID_ARGS), says why on stderr, and prints
# nothing on stdout, before any config is read. Driven through the real
# binary, so option parsing, validation and the top-level rescue are all
# exercised together.
RSpec.describe 'gitlab_ci_cli argument errors' do
  let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }
  let(:entry) { File.expand_path('../../test_ci_projects/proj1/.gitlab-ci.yml', __dir__) }

  def cli(*args)
    Open3.capture3(bin_path, *args)
  end

  {
    'an unknown flag' => [%w[lint --bogus], 'Unknown flag: --bogus'],
    'a flag without its value' => [%w[lint --output], 'Flag --output requires a value'],
    'a flag followed by another flag' => [%w[lint --gitlab-dir --verbose], 'Flag --gitlab-dir requires a value'],
    'a --format outside text/json/junit' => [%w[--format xml lint], "Invalid value 'xml' for --format. Must be one of: text, json, junit"],
    'a --run-deps outside incl/excl' => [%w[--run-deps maybe run build], "Invalid value 'maybe' for --run-deps. Must be one of: incl, excl"],
    'an invalid --pass-env name' => [%w[--pass-env FOO,1BAD run build],
                                     '--pass-env: invalid variable name "1BAD" in "FOO,1BAD": expected none, all, ' \
                                     'or names like AWS_PROFILE,SSH_AUTH_SOCK ([A-Za-z_][A-Za-z0-9_]*)'],
    'an empty name in --pass-env' => [['--pass-env', 'FOO,', 'run', 'build'],
                                     '--pass-env: invalid variable name "" in "FOO,": expected none, all, ' \
                                     'or names like AWS_PROFILE,SSH_AUTH_SOCK ([A-Za-z_][A-Za-z0-9_]*)'],
    'a mode inside a --pass-env list' => [%w[--pass-env FOO,all run build],
                                         "--pass-env: 'all' is a mode of its own, not a name to list with others: FOO,all"],
    '--pass-env twice' => [%w[--pass-env A --pass-env B run build],
                           'Flag --pass-env given twice: list every name in one comma-separated value'],
    'run without a job name' => [%w[run], "Job name required for 'run' command. Usage: gitlab_ci_cli run <job_name>"]
  }.each do |case_name, (args, message)|
    it "rejects #{case_name} with exit 1 and the reason on stderr" do
      stdout, stderr, status = cli(*args, '--entry', entry)

      expect(status.exitstatus).to eq(1)
      expect(stderr).to eq("Error: #{message}\n")
      expect(stdout).to be_empty
    end
  end

  it 'rejects a --project directory that does not exist' do
    _stdout, stderr, status = cli('lint', '--entry', entry, '--project', '/nonexistent/project')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to eq("Error: Project directory not found: /nonexistent/project\n")
  end

  it 'rejects a dry-run --runners directory that does not exist' do
    _stdout, stderr, status = cli('dry-run', '--entry', entry, '--runners', '/nonexistent/runners')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to eq("Error: Runners directory not found: /nonexistent/runners\n")
  end

  it 'does not require a runners directory for commands that do not use one' do
    _stdout, stderr, status = cli('lint', '--entry', entry, '--runners', '/nonexistent/runners')

    expect(stderr).to be_empty
    expect(status.exitstatus).to eq(0)
  end
end
