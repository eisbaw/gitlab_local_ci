# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'spec_helper'
require 'ci_keywords'

RSpec.describe CiKeywords do
  # Drift detector: fails when the gitlab/ submodule is bumped to a release
  # whose Entry::Root allows different top-level keys.
  it 'ROOT equals upstream Entry::Root::ALLOWED_KEYS' do
    root_rb = File.expand_path('../../gitlab/lib/gitlab/ci/config/entry/root.rb', __dir__)
    skip 'gitlab/ submodule not checked out' unless File.exist?(root_rb)

    upstream = File.read(root_rb)[/ALLOWED_KEYS = %i\[([^\]]+)\]/m, 1]
    expect(upstream).not_to be_nil, 'ALLOWED_KEYS not found in root.rb; update this parser'
    expect(described_class::ROOT.sort).to eq(upstream.split.sort)
  end

  it 'JOB equals the union of upstream Job, EE Job, Bridge and Processable allowed keys' do
    entry_dir = File.expand_path('../../gitlab/lib/gitlab/ci/config/entry', __dir__)
    ee_job_rb = File.expand_path('../../gitlab/ee/lib/ee/gitlab/ci/config/entry/job.rb', __dir__)
    skip 'gitlab/ submodule not checked out' unless File.exist?(ee_job_rb)

    lists = {
      File.join(entry_dir, 'job.rb') => /^\s+ALLOWED_KEYS = %i\[([^\]]+)\]/m,
      ee_job_rb => /EE_ALLOWED_KEYS = %i\[([^\]]+)\]/m,
      File.join(entry_dir, 'bridge.rb') => /ALLOWED_KEYS = %i\[([^\]]+)\]/m,
      File.join(entry_dir, 'processable.rb') => /PROCESSABLE_ALLOWED_KEYS = %i\[([^\]]+)\]/m
    }
    upstream = lists.flat_map do |file, pattern|
      keys = File.read(file)[pattern, 1]
      expect(keys).not_to be_nil, "allowed keys not found in #{file}; update this parser"
      keys.split
    end
    expect(described_class::JOB.sort).to eq(upstream.uniq.sort)
  end

  it 'classifies Hash values under non-root keys as job entries, nothing else' do
    expect(described_class.job_entry?('build', { 'script' => ['x'] })).to be true
    expect(described_class.job_entry?('.tpl', { 'script' => ['x'] })).to be true
    expect(described_class.job_entry?('image', { 'name' => 'alpine' })).to be false
    expect(described_class.job_entry?('cache', { 'paths' => ['x'] })).to be false
    expect(described_class.job_entry?('build', 'not a hash')).to be false
  end
end
