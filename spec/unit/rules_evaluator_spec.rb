# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'spec_helper'
require 'rules_evaluator'

RSpec.describe RulesEvaluator do
  describe '#evaluate' do
    subject(:evaluator) { described_class.new }

    context 'equality / inequality' do
      it 'evaluates string equality on set variables' do
        expect(evaluator.evaluate('$FOO == "bar"', { 'FOO' => 'bar' })).to be true
        expect(evaluator.evaluate('$FOO == "bar"', { 'FOO' => 'baz' })).to be false
      end

      it 'treats unset variables as nil, never equal to any string' do
        expect(evaluator.evaluate('$MISSING == "bar"', {})).to be false
        expect(evaluator.evaluate('$MISSING != "bar"', {})).to be true
      end

      it 'matches explicit-empty against empty string only via ==' do
        expect(evaluator.evaluate('$FOO == ""', { 'FOO' => '' })).to be true
        expect(evaluator.evaluate('$FOO == ""', {})).to be false
      end

      it 'supports null literal comparisons' do
        expect(evaluator.evaluate('$FOO == null', {})).to be true
        expect(evaluator.evaluate('$FOO == null', { 'FOO' => 'x' })).to be false
        expect(evaluator.evaluate('$FOO != null', { 'FOO' => 'x' })).to be true
      end
    end

    context 'regex match' do
      it 'matches set variable with =~ /.+/' do
        expect(evaluator.evaluate('$FOO =~ /.+/', { 'FOO' => 'deadbeef' })).to be true
      end

      it 'returns false for unset variable with =~ /.+/' do
        expect(evaluator.evaluate('$FOO =~ /.+/', {})).to be false
      end

      it 'returns false for empty-string variable with =~ /.+/' do
        expect(evaluator.evaluate('$FOO =~ /.+/', { 'FOO' => '' })).to be false
      end

      it 'inverts via !~ /.+/' do
        expect(evaluator.evaluate('$FOO !~ /.+/', {})).to be true
        expect(evaluator.evaluate('$FOO !~ /.+/', { 'FOO' => 'set' })).to be false
      end

      it 'honors regex flags' do
        expect(evaluator.evaluate('$FOO =~ /^bar$/i', { 'FOO' => 'BAR' })).to be true
      end
    end

    context 'boolean composition' do
      it 'supports && and ||' do
        vars = { 'A' => 'x', 'B' => 'y' }
        expect(evaluator.evaluate('$A == "x" && $B == "y"', vars)).to be true
        expect(evaluator.evaluate('$A == "x" && $B == "z"', vars)).to be false
        expect(evaluator.evaluate('$A == "x" || $B == "z"', vars)).to be true
      end

      it 'supports parentheses' do
        vars = { 'A' => 'x', 'B' => 'y', 'C' => 'z' }
        expect(evaluator.evaluate('($A == "x" || $B == "n") && $C == "z"', vars)).to be true
      end
    end

    context 'truthy evaluation of bare variables' do
      it 'treats non-empty string as truthy' do
        expect(evaluator.evaluate('$FOO', { 'FOO' => 'set' })).to be true
      end

      it 'treats empty string and missing as falsy' do
        expect(evaluator.evaluate('$FOO', { 'FOO' => '' })).to be false
        expect(evaluator.evaluate('$FOO', {})).to be false
      end
    end

    context 'malformed expressions' do
      it 'raises ParseError on unknown syntax' do
        expect { evaluator.evaluate('$A === "x"', {}) }
          .to raise_error(RulesEvaluator::ParseError)
      end
    end
  end

  describe '.evaluate_rules' do
    it 'returns matched=false when no rule matches' do
      rules = [{ 'if' => '$FOO == "x"' }, { 'if' => '$BAR == "y"' }]
      result = described_class.evaluate_rules(rules, {})
      expect(result).to include(matched: false, when: nil)
    end

    it 'returns the first match' do
      rules = [
        { 'if' => '$FOO == "x"' },
        { 'if' => '$BAR == "y"', 'when' => 'manual' },
      ]
      result = described_class.evaluate_rules(rules, { 'BAR' => 'y' })
      expect(result).to include(matched: true, when: 'manual')
    end

    it 'treats a rule without if as an unconditional match' do
      rules = [{ 'if' => '$FOO == "x"' }, { 'when' => 'always' }]
      result = described_class.evaluate_rules(rules, {})
      expect(result).to include(matched: true, when: 'always')
    end

    it 'returns matched=true and when=nil when rules is nil' do
      expect(described_class.evaluate_rules(nil, {})).to include(matched: true, when: nil)
    end

    it 'enforces mutually-exclusive include rules across topic pipelines' do
      # exactly one include rule among the topic pipelines should match
      module_a_rule = '$SUBMODULE_UPDATE != "true" && $CI_PIPELINE_SOURCE != "schedule" && $COMMIT_MODULE_B !~ /.+/ && $COMMIT_MODULE_C !~ /.+/ && $COMMIT_MODULE_D !~ /.+/ && $COMMIT_MODULE_A =~ /.+/'
      module_b_rule = '$SUBMODULE_UPDATE != "true" && $CI_PIPELINE_SOURCE != "schedule" && $COMMIT_MODULE_B =~ /.+/ && $COMMIT_MODULE_C !~ /.+/ && $COMMIT_MODULE_D !~ /.+/ && $COMMIT_MODULE_A !~ /.+/'

      vars_a = { 'COMMIT_MODULE_A' => 'deadbeef' }
      vars_b = { 'COMMIT_MODULE_B' => 'cafef00d' }

      expect(described_class.new.evaluate(module_a_rule, vars_a)).to be true
      expect(described_class.new.evaluate(module_b_rule, vars_a)).to be false
      expect(described_class.new.evaluate(module_a_rule, vars_b)).to be false
      expect(described_class.new.evaluate(module_b_rule, vars_b)).to be true
    end
  end
end
