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
require 'config_merge'

# Reference semantics: ActiveSupport Hash#deep_merge as used by upstream
# External::Processor and Extendable::Entry.
RSpec.describe ConfigMerge do
  describe '.deep_merge' do
    it 'merges nested hashes at any depth' do
      base = { 'variables' => { 'A' => '1' }, 'job' => { 'artifacts' => { 'when' => 'always' } } }
      overlay = { 'variables' => { 'B' => '2' }, 'job' => { 'artifacts' => { 'expire_in' => '1d' } } }

      expect(described_class.deep_merge(base, overlay)).to eq(
        'variables' => { 'A' => '1', 'B' => '2' },
        'job' => { 'artifacts' => { 'when' => 'always', 'expire_in' => '1d' } }
      )
    end

    it 'replaces arrays at any depth instead of concatenating' do
      base = { 'stages' => %w[a b], 'job' => { 'artifacts' => { 'paths' => ['x'] } } }
      overlay = { 'stages' => ['c'], 'job' => { 'artifacts' => { 'paths' => ['y'] } } }

      result = described_class.deep_merge(base, overlay)

      expect(result['stages']).to eq(['c'])
      expect(result['job']['artifacts']['paths']).to eq(['y'])
    end

    it 'lets a non-hash overlay replace a hash and vice versa' do
      expect(described_class.deep_merge({ 'k' => { 'a' => 1 } }, { 'k' => 'str' })).to eq('k' => 'str')
      expect(described_class.deep_merge({ 'k' => 'str' }, { 'k' => { 'a' => 1 } })).to eq('k' => { 'a' => 1 })
      expect(described_class.deep_merge({ 'k' => ['x'] }, { 'k' => nil })).to eq('k' => nil)
    end

    it 'keeps base key positions and appends overlay-only keys' do
      result = described_class.deep_merge({ 'a' => 1, 'b' => 2 }, { 'c' => 3, 'a' => 9 })
      expect(result.keys).to eq(%w[a b c])
    end

    it 'shares no mutable structure with its inputs' do
      base = { 'h' => { 'arr' => ['b'] }, 'only_base' => ['x'] }
      overlay = { 'h' => { 'arr2' => ['o'] }, 'only_overlay' => { 'k' => 's' } }

      result = described_class.deep_merge(base, overlay)
      result['h']['arr'] << 'mutated'
      result['h']['arr2'] << 'mutated'
      result['only_base'] << 'mutated'
      result['only_overlay']['k'] << 'mutated'

      expect(base).to eq('h' => { 'arr' => ['b'] }, 'only_base' => ['x'])
      expect(overlay).to eq('h' => { 'arr2' => ['o'] }, 'only_overlay' => { 'k' => 's' })
    end

    it 'rejects non-hash arguments' do
      expect { described_class.deep_merge(nil, {}) }.to raise_error(ArgumentError, /base must be a Hash/)
      expect { described_class.deep_merge({}, ['x']) }.to raise_error(ArgumentError, /overlay must be a Hash/)
    end

    # Randomised laws over nested string/array/hash trees (seeded, bounded).
    # Deliberately NOT associativity: deep_merge is not associative when a
    # hash/non-hash/hash sequence hits one key, which is why include and
    # extends must merge in exactly upstream's tree order.
    context 'with random nested configs' do
      def random_tree(rng, depth)
        return rng.rand(3).to_s if depth.zero? || rng.rand < 0.3
        return Array.new(rng.rand(3)) { random_tree(rng, depth - 1) } if rng.rand < 0.3

        Array.new(rng.rand(4)) { ["k#{rng.rand(4)}", random_tree(rng, depth - 1)] }.to_h
      end

      def random_hash(rng)
        tree = random_tree(rng, 4)
        tree.is_a?(Hash) ? tree : { 'root' => tree }
      end

      let(:rng) { Random.new(20_261_109) }

      it 'satisfies identity, idempotence, and overlay-wins-on-leaves for 500 samples' do
        500.times do
          a = random_hash(rng)
          b = random_hash(rng)
          merged = described_class.deep_merge(a, b)

          expect(described_class.deep_merge(a, {})).to eq(a)
          expect(described_class.deep_merge({}, b)).to eq(b)
          expect(described_class.deep_merge(a, a)).to eq(a)
          expect(merged.keys).to eq((a.keys + b.keys).uniq)
          b.each do |key, value|
            if a[key].is_a?(Hash) && value.is_a?(Hash)
              expect(merged[key]).to eq(described_class.deep_merge(a[key], value))
            else
              expect(merged[key]).to eq(value)
            end
          end
        end
      end
    end
  end
end
