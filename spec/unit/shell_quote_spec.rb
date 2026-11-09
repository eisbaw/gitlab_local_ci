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
require_relative '../../lib/shell_quote'

RSpec.describe ShellQuote do
  # Behaviour, not shape: bash reads every quoted word back verbatim. One
  # bash for all words (per-word processes would dominate the run time).
  it 'quotes any NUL-free text so bash reads it back verbatim, and refuses NUL' do
    seed = 20_261_110
    random = Random.new(seed)
    alphabet = ["'", '"', '\\', '$', '`', '$(', '!', '*', ' ', "\n", "\r", "\t", '{{', '#', ';', '&', '|', 'a', 'é', "\e"]
    words = ['', "'", "''", "a'b", "\n"] +
            Array.new(200) { Array.new(random.rand(0..12)) { alphabet.sample(random: random) }.join }
    program = words.map { |word| "printf '%s\\0' #{described_class.quote(word)}" }.join("\n")
    stdout, stderr, status = Open3.capture3('bash', '-c', program)
    expect(status.success?).to be(true), stderr
    expect(stdout.force_encoding(Encoding::UTF_8).split("\0", -1)[0...-1]).to eq(words), "seed #{seed}"

    expect { described_class.quote("a\0b") }.to raise_error(ArgumentError, /NUL/)
  end
end
