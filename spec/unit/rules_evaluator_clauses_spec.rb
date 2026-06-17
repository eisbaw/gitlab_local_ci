# frozen_string_literal: true

require 'spec_helper'
require 'rules_evaluator'
require 'tmpdir'
require 'fileutils'
require 'open3'

RSpec.describe RulesEvaluator do
  before { described_class.reset_warnings! }

  # ----- Gap 1: exists: clause ------------------------------------------

  describe 'exists: clause' do
    it 'matches a literal top-level file' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'Justfile'), '')
        rules = [{ 'exists' => ['Justfile'] }]
        result = described_class.evaluate_rules(rules, {}, context: { project_dir: dir })
        expect(result[:matched]).to be true
      end
    end

    it 'does not match an absent file' do
      Dir.mktmpdir do |dir|
        rules = [{ 'exists' => ['does-not-exist.txt'] }]
        result = described_class.evaluate_rules(rules, {}, context: { project_dir: dir })
        expect(result[:matched]).to be false
      end
    end

    it 'matches deep glob via **/*.ext' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'src', 'sub'))
        File.write(File.join(dir, 'src', 'sub', 'mod.rb'), '')
        rules = [{ 'exists' => ['**/*.rb'] }]
        result = described_class.evaluate_rules(rules, {}, context: { project_dir: dir })
        expect(result[:matched]).to be true
      end
    end

    it 'accepts hash form { paths: [...] }' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.txt'), '')
        rules = [{ 'exists' => { 'paths' => ['a.txt'] } }]
        result = described_class.evaluate_rules(rules, {}, context: { project_dir: dir })
        expect(result[:matched]).to be true
      end
    end

    it 'interpolates $VAR in patterns' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'lookup.yml'), '')
        rules = [{ 'exists' => ['$NAME.yml'] }]
        result = described_class.evaluate_rules(rules, { 'NAME' => 'lookup' }, context: { project_dir: dir })
        expect(result[:matched]).to be true
      end
    end
  end

  # ----- Gap 2: changes: clause -----------------------------------------

  describe 'changes: clause' do
    it 'matches when a file is uncommitted-modified' do
      Dir.mktmpdir do |dir|
        Open3.capture3('git', '-C', dir, 'init', '-q', '-b', 'main')
        Open3.capture3('git', '-C', dir, 'config', 'user.email', 't@t')
        Open3.capture3('git', '-C', dir, 'config', 'user.name',  't')
        File.write(File.join(dir, 'src.rb'), 'a')
        Open3.capture3('git', '-C', dir, 'add', '.')
        Open3.capture3('git', '-C', dir, 'commit', '-q', '-m', 'init')
        # Local modification.
        File.write(File.join(dir, 'src.rb'), 'a\nb')

        rules = [{ 'changes' => ['*.rb'] }]
        result = described_class.evaluate_rules(rules, {}, context: { project_dir: dir, default_branch: 'main' })
        expect(result[:matched]).to be true
      end
    end

    it 'matches with hash form { paths: [...] }' do
      Dir.mktmpdir do |dir|
        Open3.capture3('git', '-C', dir, 'init', '-q', '-b', 'main')
        Open3.capture3('git', '-C', dir, 'config', 'user.email', 't@t')
        Open3.capture3('git', '-C', dir, 'config', 'user.name',  't')
        File.write(File.join(dir, 'a.rb'), 'a')
        Open3.capture3('git', '-C', dir, 'add', '.')
        Open3.capture3('git', '-C', dir, 'commit', '-q', '-m', 'init')
        File.write(File.join(dir, 'a.rb'), 'b')

        rules = [{ 'changes' => { 'paths' => ['*.rb'] } }]
        result = described_class.evaluate_rules(rules, {}, context: { project_dir: dir, default_branch: 'main' })
        expect(result[:matched]).to be true
      end
    end

    it 'matches TRUE with warning when git is unavailable' do
      Dir.mktmpdir do |dir|
        rules = [{ 'changes' => ['*.rb'] }]
        captured = capture_stderr do
          @result = described_class.evaluate_rules(rules, {}, context: { project_dir: dir })
        end
        expect(@result[:matched]).to be true
        expect(captured).to match(/changes: git diff unavailable/)
      end
    end
  end

  # ----- Gap 5: per-rule attributes -------------------------------------

  describe 'per-rule attribute extraction' do
    it 'returns variables/allow_failure/needs/etc on attributes' do
      rules = [
        {
          'if' => '$X == "1"',
          'when' => 'manual',
          'variables' => { 'FOO' => 'bar' },
          'allow_failure' => true,
          'needs' => ['build'],
          'interruptible' => false,
          'start_in' => '5 minutes'
        }
      ]
      result = described_class.evaluate_rules(rules, { 'X' => '1' })
      expect(result[:when]).to eq('manual')
      attrs = result[:attributes]
      expect(attrs['variables']).to eq('FOO' => 'bar')
      expect(attrs['allow_failure']).to be true
      expect(attrs['needs']).to eq(['build'])
      expect(attrs['interruptible']).to be false
      expect(attrs['start_in']).to eq('5 minutes')
    end
  end

  # ----- Gap 7: interpolation in string + regex literals ----------------

  describe 'literal interpolation' do
    it 'expands $VAR inside a string literal' do
      vars = { 'CI_DEFAULT_BRANCH' => 'main' }
      result = described_class.new.evaluate('$REF == "$CI_DEFAULT_BRANCH"', vars.merge('REF' => 'main'))
      expect(result).to be true
    end

    it 'expands $VAR inside a regex literal' do
      vars = { 'CI_DEFAULT_BRANCH' => 'main', 'REF' => 'main-feature-x' }
      result = described_class.new.evaluate('$REF =~ /^$CI_DEFAULT_BRANCH-feature-.+/', vars)
      expect(result).to be true
    end

    it 'expands unknown $VAR to empty string' do
      result = described_class.new.evaluate('$REF == "$UNSET"', { 'REF' => '' })
      expect(result).to be true
    end
  end

  # ----- Gap 8 + 9: regex flags and Onigmo divergence warnings ----------

  describe 'regex flags + onigmo warnings' do
    it 'rejects unknown flag chars' do
      expect do
        described_class.new.evaluate('$F =~ /x/Q', { 'F' => 'x' })
      end.to raise_error(RulesEvaluator::ParseError, /Unknown regex flag/)
    end

    it 'accepts U flag with one-time warning' do
      captured = capture_stderr do
        described_class.new.evaluate('$F =~ /x/U', { 'F' => 'x' })
        described_class.new.evaluate('$F =~ /y/U', { 'F' => 'y' })
      end
      expect(captured).to include("regex flag 'U'")
    end

    it 'warns on lookbehind' do
      captured = capture_stderr do
        described_class.new.evaluate('$F =~ /(?<=foo)bar/', { 'F' => 'foobar' })
      end
      expect(captured).to match(/Onigmo construct: lookbehind/)
    end

    it 'warns on atomic group' do
      captured = capture_stderr do
        described_class.new.evaluate('$F =~ /(?>abc)/', { 'F' => 'abc' })
      end
      expect(captured).to match(/Onigmo construct: atomic group/)
    end
  end

  # ----- Gap 10: include-rule when validation ---------------------------

  describe 'include-rule when validation' do
    it 'allows when: never and when: always for include rules' do
      rules = [{ 'if' => '$X == "1"', 'when' => 'never' }]
      expect do
        described_class.evaluate_rules(rules, { 'X' => '1' }, mode: :include)
      end.not_to raise_error
    end

    it 'rejects when: manual on include rules' do
      rules = [{ 'if' => '$X == "1"', 'when' => 'manual' }]
      expect do
        described_class.evaluate_rules(rules, { 'X' => '1' }, mode: :include)
      end.to raise_error(RulesEvaluator::ParseError, /include: rules:when/)
    end

    it 'allows when: manual on job rules' do
      rules = [{ 'if' => '$X == "1"', 'when' => 'manual' }]
      expect do
        described_class.evaluate_rules(rules, { 'X' => '1' }, mode: :job)
      end.not_to raise_error
    end

    it 'rejects nonsense when: even on job rules' do
      rules = [{ 'if' => '$X == "1"', 'when' => 'sometime' }]
      expect do
        described_class.evaluate_rules(rules, { 'X' => '1' }, mode: :job)
      end.to raise_error(RulesEvaluator::ParseError)
    end
  end
end
