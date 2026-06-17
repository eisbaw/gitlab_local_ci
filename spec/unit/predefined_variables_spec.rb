# frozen_string_literal: true

require 'spec_helper'
require 'predefined_variables'
require 'tmpdir'
require 'open3'

RSpec.describe PredefinedVariables do
  describe '.slugify' do
    it 'lowercases and replaces non-alnum with dashes' do
      expect(described_class.slugify('Feature/My-Branch.1')).to eq('feature-my-branch-1')
    end

    it 'truncates to 63 chars' do
      expect(described_class.slugify('a' * 100).length).to eq(63)
    end

    it 'returns empty string for nil or empty input' do
      expect(described_class.slugify(nil)).to eq('')
      expect(described_class.slugify('')).to eq('')
    end

    it 'strips leading/trailing dashes after slugify' do
      expect(described_class.slugify('---foo---')).to eq('foo')
    end
  end

  describe '.build' do
    it 'sets project, source, and falls back to safe defaults outside a git repo' do
      Dir.mktmpdir do |dir|
        vars = described_class.build(project_dir: dir, pipeline_source: 'push')
        expect(vars['CI_PROJECT_DIR']).to eq(File.expand_path(dir))
        expect(vars['CI_PROJECT_NAME']).to eq(File.basename(dir))
        expect(vars['CI_PROJECT_PATH']).to eq(File.basename(dir))
        expect(vars['CI_PIPELINE_SOURCE']).to eq('push')
        # No git repo: branch/tag/sha must be empty strings, not nil.
        expect(vars['CI_COMMIT_BRANCH']).to eq('')
        expect(vars['CI_COMMIT_TAG']).to eq('')
        expect(vars['CI_COMMIT_SHA']).to eq('')
        expect(vars['CI_COMMIT_SHORT_SHA']).to eq('')
        expect(vars['CI_DEFAULT_BRANCH']).to eq('main')
      end
    end

    it 'populates branch + sha inside a real git repo' do
      Dir.mktmpdir do |dir|
        Open3.capture3('git', '-C', dir, 'init', '-q', '-b', 'main')
        Open3.capture3('git', '-C', dir, 'config', 'user.email', 't@t')
        Open3.capture3('git', '-C', dir, 'config', 'user.name', 't')
        File.write(File.join(dir, 'f'), 'x')
        Open3.capture3('git', '-C', dir, 'add', '.')
        Open3.capture3('git', '-C', dir, 'commit', '-q', '-m', 'init')

        vars = described_class.build(project_dir: dir, pipeline_source: 'push')
        expect(vars['CI_COMMIT_BRANCH']).to eq('main')
        expect(vars['CI_COMMIT_SHA']).to match(/\A[0-9a-f]{40}\z/)
        expect(vars['CI_COMMIT_SHORT_SHA'].length).to eq(8)
        expect(vars['CI_COMMIT_REF_NAME']).to eq('main')
        expect(vars['CI_COMMIT_REF_SLUG']).to eq('main')
      end
    end

    it 'sets CI_JOB_NAME and CI_JOB_STAGE only when supplied' do
      Dir.mktmpdir do |dir|
        plain = described_class.build(project_dir: dir)
        expect(plain).not_to have_key('CI_JOB_NAME')
        expect(plain).not_to have_key('CI_JOB_STAGE')

        scoped = described_class.build(project_dir: dir, job_name: 'lint', job_stage: 'test')
        expect(scoped['CI_JOB_NAME']).to eq('lint')
        expect(scoped['CI_JOB_STAGE']).to eq('test')
      end
    end

    it 'sets CI_MERGE_REQUEST_* only for merge_request pipeline source' do
      Dir.mktmpdir do |dir|
        push = described_class.build(project_dir: dir, pipeline_source: 'push')
        expect(push).not_to have_key('CI_MERGE_REQUEST_IID')

        mr = described_class.build(project_dir: dir, pipeline_source: 'merge_request')
        expect(mr).to have_key('CI_MERGE_REQUEST_IID')
        expect(mr).to have_key('CI_MERGE_REQUEST_SOURCE_BRANCH_NAME')
        expect(mr).to have_key('CI_MERGE_REQUEST_TARGET_BRANCH_NAME')
      end
    end
  end
end
