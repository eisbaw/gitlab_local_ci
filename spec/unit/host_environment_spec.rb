# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'spec_helper'
require_relative '../../lib/host_environment'

# --pass-env (TASK-56). Behaviour through run/export-just is in the
# integration specs; this pins the parser and the selection.
RSpec.describe HostEnvironment do
  let(:host) do
    { 'PATH' => '/bin', 'HOME' => '/h', 'LC_TIME' => 'C', 'LCX' => 'no', 'CI_JOB_ID' => '999',
      'GITLAB_CI' => 'true', 'FOO' => 'foo', 'BAR' => 'bar' }
  end

  describe '.parse' do
    it 'reads none, all and a name list' do
      expect(described_class.parse('none')).to eq([])
      expect(described_class.parse('all')).to eq(:all)
      expect(described_class.parse('FOO,_x1,FOO')).to eq(%w[FOO _x1])
    end

    ['', ',', 'FOO,', '1FOO', 'FOO-BAR', 'FOO BAR', 'FOO=1', 'LC_*', "FOO\nBAR", 'none,FOO', 'FOO,all'].each do |text|
      it "rejects #{text.inspect}" do
        expect { described_class.parse(text) }.to raise_error(ArgumentError, /--pass-env/)
      end
    end
  end

  describe '.select' do
    it 'passes only the base by default: no CI_*, GITLAB_* or other host variables' do
      expect(described_class.select(host, [])).to eq('PATH' => '/bin', 'HOME' => '/h', 'LC_TIME' => 'C')
    end

    it 'adds listed names that are set' do
      expect(described_class.select(host, %w[FOO MISSING])).to eq('PATH' => '/bin', 'HOME' => '/h', 'LC_TIME' => 'C',
                                                                  'FOO' => 'foo')
    end

    it 'passes everything under all' do
      expect(described_class.select(host, :all)).to eq(host)
    end

    it 'refuses a list name that is not an identifier (a recipe writes them unquoted)' do
      expect { described_class.passed_names(['A;rm']) }.to raise_error(ArgumentError, /invalid variable name/)
      expect { described_class.passed_names(:all) }.to raise_error(ArgumentError, /must be a list/)
    end
  end
end
