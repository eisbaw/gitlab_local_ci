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
require 'extends_resolver'
require 'yaml'
require 'tmpdir'
require_relative '../../lib/commands/lint_command'

# Reference: upstream Extendable::Entry#extend! (gitlab/ submodule):
#   merged = {}; base_hashes!.each { |h| merged.deep_merge!(h) }
#   merged.deep_merge!(value)
# ActiveSupport deep_merge!: hashes merge, arrays (and scalars) replace.
RSpec.describe ExtendsResolver do
  def resolve(yaml)
    described_class.new.resolve_extends(YAML.safe_load(yaml))
  end

  # job -> .l1 -> ... -> .l<edges>; .l<edges> has no extends.
  def chain_yaml(edges)
    lines = ["job: {extends: .l1, script: [echo]}"]
    (1...edges).each { |i| lines << ".l#{i}: {extends: .l#{i + 1}}" }
    lines << ".l#{edges}: {stage: test}"
    lines.join("\n")
  end

  describe '#resolve_extends' do
    it 'replaces parent arrays with child arrays (TASK-6 repro)' do
      config = resolve(<<~YAML)
        .base: {tags: [a], before_script: [echo base]}
        t: {extends: .base, tags: [a], before_script: [echo child], script: [echo t]}
      YAML

      expect(config['t']).to eq(
        'tags' => ['a'], 'before_script' => ['echo child'], 'script' => ['echo t']
      )
    end

    it 'replaces arrays nested in hashes and deep-merges the hashes' do
      config = resolve(<<~YAML)
        .base:
          artifacts: {paths: [x], expire_in: 1d, reports: {junit: a.xml}}
          cache: {key: k, paths: [vendor]}
          variables: {A: base, B: base}
          needs: [prep]
          after_script: [base]
        job:
          extends: .base
          artifacts: {paths: [y], reports: {dotenv: b.env}}
          cache: {paths: [node_modules]}
          variables: {B: child}
          needs: [other]
          after_script: [child]
          script: [echo]
      YAML

      expect(config['job']).to eq(
        'artifacts' => { 'paths' => ['y'], 'expire_in' => '1d',
                         'reports' => { 'junit' => 'a.xml', 'dotenv' => 'b.env' } },
        'cache' => { 'key' => 'k', 'paths' => ['node_modules'] },
        'variables' => { 'A' => 'base', 'B' => 'child' },
        'needs' => ['other'],
        'after_script' => ['child'],
        'script' => ['echo']
      )
    end

    it 'inherits parent arrays the child does not set' do
      config = resolve(<<~YAML)
        .base: {tags: [docker], before_script: [setup]}
        job: {extends: .base, script: [echo]}
      YAML

      expect(config['job']).to eq('tags' => ['docker'], 'before_script' => ['setup'], 'script' => ['echo'])
    end

    it 'applies multi-level extends bottom-up, nearest ancestor winning' do
      config = resolve(<<~YAML)
        .a: {stage: build, tags: [a], variables: {X: a, A: a}}
        .b: {extends: .a, tags: [b], variables: {X: b}}
        job: {extends: .b, script: [echo], variables: {J: j}}
      YAML

      expect(config['job']).to eq(
        'stage' => 'build', 'tags' => ['b'],
        'variables' => { 'X' => 'b', 'A' => 'a', 'J' => 'j' },
        'script' => ['echo']
      )
    end

    it 'applies multiple parents in order: later parent wins, the job wins last' do
      config = resolve(<<~YAML)
        .p1: {image: one, tags: [p1], before_script: [p1], variables: {V: p1, ONLY1: x}}
        .p2: {image: two, tags: [p2], variables: {V: p2}}
        job: {extends: [.p1, .p2], tags: [job], script: [echo]}
      YAML

      expect(config['job']).to eq(
        'image' => 'two', 'tags' => ['job'], 'before_script' => ['p1'],
        'variables' => { 'V' => 'p2', 'ONLY1' => 'x' }, 'script' => ['echo']
      )
    end

    it 'does not leak one child into a template shared with another child' do
      config = resolve(<<~YAML)
        .base: {tags: [shared], variables: {V: base}}
        a: {extends: .base, script: [a]}
        b: {extends: .base, script: [b]}
      YAML
      config['a']['tags'] << 'mutated'
      config['a']['variables']['V'] = 'mutated'

      expect(config['b']).to eq('tags' => ['shared'], 'variables' => { 'V' => 'base' }, 'script' => ['b'])
      expect(config['.base']).to eq('tags' => ['shared'], 'variables' => { 'V' => 'base' })
    end

    it 'can extend a non-hidden job' do
      config = resolve(<<~YAML)
        build: {stage: build, script: [make], tags: [x]}
        build2: {extends: build, tags: [y]}
      YAML

      expect(config['build2']).to eq('stage' => 'build', 'script' => ['make'], 'tags' => ['y'])
    end

    # Upstream Entry#nesting_too_deep?: ancestors.count > MAX_NESTING_LEVELS (10),
    # checked on an entry that itself extends. So 11 extends edges below a job
    # are allowed ("as many as eleven" levels, yaml_optimization.md) and the
    # 12th is rejected.
    it 'allows 11 levels of extends' do
      expect(resolve(chain_yaml(11))['job']).to eq('stage' => 'test', 'script' => ['echo'])
    end

    it 'rejects 12 levels of extends with the upstream message' do
      expect { resolve(chain_yaml(12)) }
        .to raise_error(ExtendsResolver::NestingTooDeepError, '.l11: nesting too deep in `extends`')
    end

    it 'still detects circular extends' do
      expect { resolve(".a: {extends: .b}\n.b: {extends: .a}\njob: {extends: .a}\n") }
        .to raise_error(/[Cc]ircular/)
    end

    it 'reports an unknown parent' do
      expect { resolve("job: {extends: .missing, script: [x]}\n") }
        .to raise_error(/\.missing/)
    end
  end

  describe 'key order' do
    # Upstream Extendable::Entry#extend! writes each merged entry back in
    # place; lint's job list and dry-run dispatch order depend on it.
    it 'keeps every top-level key at its position' do
      result = resolve(<<~YAML)
        first:
          script: [echo]
        .tpl:
          stage: build
        stages: [build, test]
        child:
          extends: .tpl
          script: [echo]
        cache:
          paths: [x]
        last:
          script: [echo]
      YAML
      expect(result.keys).to eq(%w[first .tpl stages child cache last])
      expect(result['child']).to eq('stage' => 'build', 'script' => ['echo'])
    end
  end

  describe 'via lint' do
    it 'reports too-deep extends nesting as a lint error' do
      Dir.mktmpdir do |dir|
        entry = File.join(dir, '.gitlab-ci.yml')
        File.write(entry, chain_yaml(12))

        result = Commands::LintCommand.execute(entry: entry)

        expect(result.valid).to be false
        expect(result.exit_code).to eq 1
        expect(result.errors).to include('Error resolving extends: .l11: nesting too deep in `extends`')
      end
    end
  end
end
