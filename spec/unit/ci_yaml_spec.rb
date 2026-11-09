# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'spec_helper'
require 'yaml'
require 'ci_yaml'

RSpec.describe CiYaml do
  it 'keeps the !reference tag as a Reference, distinct from a literal list' do
    loaded = described_class.load("a: !reference [.x, script]\nb: [.x, script]\n")
    expect(loaded['a']).to eq(CiYaml::Reference.new(data: ['.x', 'script']))
    expect(loaded['b']).to eq(['.x', 'script'])
  end

  it 'keeps YAML anchors on a tagged node' do
    loaded = described_class.load("a: &r !reference [.x, y]\nb: *r\n")
    expect(loaded['b']).to equal(loaded['a'])
  end

  it 'still rejects tags safe_load rejects' do
    expect { described_class.load("a: !ruby/object:Object {}\n") }.to raise_error(Psych::DisallowedClass)
  end

  it 'returns nil for an empty document, like safe_load' do
    expect(described_class.load('')).to be_nil
  end

  # Differential check against the loader it replaces, over every CI file in
  # the repo's test projects and fixtures, and upstream's CI templates when
  # the gitlab/ submodule is present, that has no !reference.
  it 'equals YAML.safe_load on every untagged config in the repo' do
    root = File.expand_path('../..', __dir__)
    files = Dir.glob(File.join(root, '{test_ci_projects,spec/fixtures,gitlab/lib/gitlab/ci/templates}/**/*.{yml,yaml}'),
                      File::FNM_DOTMATCH)
    compared = 0
    files.each do |file|
      content = File.read(file)
      next if content.include?('!reference')

      expected = begin
        YAML.safe_load(content, permitted_classes: [Symbol], aliases: true)
      rescue Psych::Exception
        next expect { described_class.load(content) }.to raise_error(Psych::Exception)
      end
      expect(described_class.load(content)).to eq(expected), file
      compared += 1
    end
    expect(compared).to be >= 30
  end
end
