# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'spec_helper'
require 'predefined_variables'
require 'tmpdir'
require 'open3'

# Reference: gitlab/doc/ci/variables/predefined_variables.md,
# gitlab/lib/gitlab/ci/variables/builder/pipeline.rb, builder.rb,
# gitlab/app/models/project.rb#predefined_project_variables,
# gitlab/app/models/merge_request.rb#predefined_variables,
# gitlab/app/models/concerns/ci/has_ref.rb#branch?,
# gitlab/app/models/concerns/enums/ci/pipeline.rb.
RSpec.describe PredefinedVariables do
  let(:sha) { 'a' * 40 }
  let(:git) do
    { sha: sha, default_branch: 'main', remote_url: 'git@gitlab.example.com:group/sub/proj.git',
      commit_message: "Fix it\n\nbody line\n", commit: { epoch: 0, author_name: 'A B', author_email: 'a@b' } }
  end
  let(:branch) { described_class::Ref.new(kind: :branch, name: 'feature/X') }
  let(:tag) { described_class::Ref.new(kind: :tag, name: 'v1.0') }

  def vars(source: 'push', ref: branch, facts: git)
    described_class.pipeline_variables(project_dir: '/work/proj', source: source, ref: ref, git: facts)
  end

  describe '.canonical_source' do
    it 'maps the old names to upstream ones' do
      expect(described_class.canonical_source('merge_request')).to eq('merge_request_event')
      expect(described_class.canonical_source('manual')).to eq('web')
      expect(described_class.canonical_source('schedule')).to eq('schedule')
    end

    it 'rejects a name upstream does not have' do
      expect { described_class.canonical_source('nightly') }.to raise_error(ArgumentError, /nightly/)
    end
  end

  # The variables the standard MR rules read, per pipeline type
  # (AC: branch, tag and MR pipelines evaluate like GitLab).
  describe '.pipeline_variables by pipeline type' do
    it 'branch pipeline: CI_COMMIT_BRANCH set, no tag, no MR variables' do
      v = vars
      expect(v).to include('CI_COMMIT_BRANCH' => 'feature/X', 'CI_COMMIT_REF_NAME' => 'feature/X',
                           'CI_COMMIT_REF_SLUG' => 'feature-x', 'CI_PIPELINE_SOURCE' => 'push')
      expect(v.keys).not_to include('CI_COMMIT_TAG', 'CI_MERGE_REQUEST_IID', 'CI_OPEN_MERGE_REQUESTS')
    end

    it 'tag pipeline: CI_COMMIT_TAG set, CI_COMMIT_BRANCH unset' do
      v = vars(ref: tag)
      expect(v).to include('CI_COMMIT_TAG' => 'v1.0', 'CI_COMMIT_REF_NAME' => 'v1.0', 'CI_COMMIT_REF_SLUG' => 'v1-0')
      expect(v.keys).not_to include('CI_COMMIT_BRANCH', 'CI_MERGE_REQUEST_IID')
    end

    it 'MR pipeline: merge_request_event, MR variables set, CI_COMMIT_BRANCH and CI_COMMIT_TAG unset' do
      v = vars(source: 'merge_request_event')
      expect(v).to include(
        'CI_PIPELINE_SOURCE' => 'merge_request_event',
        'CI_MERGE_REQUEST_IID' => '1',
        'CI_MERGE_REQUEST_EVENT_TYPE' => 'detached',
        'CI_MERGE_REQUEST_SOURCE_BRANCH_NAME' => 'feature/X',
        'CI_MERGE_REQUEST_TARGET_BRANCH_NAME' => 'main',
        'CI_MERGE_REQUEST_SOURCE_BRANCH_SHA' => '',
        'CI_MERGE_REQUEST_TARGET_BRANCH_SHA' => '',
        'CI_MERGE_REQUEST_PROJECT_PATH' => 'group/sub/proj',
        'CI_COMMIT_REF_NAME' => 'feature/X'
      )
      expect(v.keys).not_to include('CI_COMMIT_BRANCH', 'CI_COMMIT_TAG')
    end

    it 'unknown ref (detached HEAD, no tag): no ref variables at all' do
      v = vars(ref: nil)
      expect(v.keys).not_to include('CI_COMMIT_BRANCH', 'CI_COMMIT_TAG', 'CI_COMMIT_REF_NAME', 'CI_COMMIT_REF_SLUG')
      expect(v['CI_COMMIT_SHA']).to eq(sha)
    end

    it 'asserts an MR pipeline has a branch ref (resolve_ref reports it to the user)' do
      expect { vars(source: 'merge_request_event', ref: tag) }.to raise_error(ArgumentError)
      expect { vars(source: 'merge_request_event', ref: nil) }.to raise_error(ArgumentError)
    end

    # Unset, not empty, across every source and ref kind: the only ''
    # values are ones upstream itself sets empty: the two SHAs in a
    # detached MR pipeline, and the message/description of a commit whose
    # message is blank or one line.
    it 'never emits an empty value except where upstream does' do
      allowed_empty = %w[CI_MERGE_REQUEST_SOURCE_BRANCH_SHA CI_MERGE_REQUEST_TARGET_BRANCH_SHA
                         CI_COMMIT_MESSAGE CI_COMMIT_DESCRIPTION]
      facts_variants = [git, {}, git.merge(remote_url: nil), git.merge(commit_message: '', default_branch: nil)]
      described_class::SOURCES.product([branch, tag, nil], facts_variants).each do |source, ref, facts|
        next if source == 'merge_request_event' && ref&.kind != :branch

        empty = vars(source: source, ref: ref, facts: facts).select { |_k, v| v.empty? }.keys
        expect(empty - allowed_empty).to eq([]), "#{source} #{ref.inspect} #{facts}"
      end
    end
  end

  describe '.pipeline_variables, always-set and derived variables' do
    it 'sets CI and GITLAB_CI to true' do
      expect(vars).to include('CI' => 'true', 'GITLAB_CI' => 'true')
    end

    it 'derives the project path from origin: namespace/name' do
      expect(vars).to include(
        'CI_PROJECT_PATH' => 'group/sub/proj', 'CI_PROJECT_NAME' => 'proj',
        'CI_PROJECT_PATH_SLUG' => 'group-sub-proj', 'CI_PROJECT_NAMESPACE' => 'group/sub',
        'CI_PROJECT_NAMESPACE_SLUG' => 'group-sub', 'CI_PROJECT_ROOT_NAMESPACE' => 'group',
        'CI_PROJECT_ROOT_NAMESPACE_SLUG' => 'group', 'CI_PROJECT_DIR' => '/work/proj'
      )
    end

    it 'falls back to the directory name without namespace variables when origin is unknown' do
      v = vars(facts: git.merge(remote_url: '/local/path/repo'))
      expect(v).to include('CI_PROJECT_PATH' => 'proj', 'CI_PROJECT_NAME' => 'proj')
      expect(v.keys).not_to include('CI_PROJECT_NAMESPACE', 'CI_PROJECT_ROOT_NAMESPACE')
    end

    it 'never emits remote credentials, also from malformed URLs: falls back to the directory name' do
      random = Random.new(20_261_110)
      urls = ['https://u:p/w@gitlab.example.com/group/proj', 'u:pa/ss@gitlab.example.com:group/proj.git']
      urls += Array.new(50) do
        secret = "S#{Array.new(8) { ['/', '@', ':', 'x', '%2F', '?', '#'].sample(random: random) }.join}S"
        ["https://user:#{secret}@host/group/proj.git", "ssh://#{secret}@host/group/proj", "#{secret}@host:group/proj"]
          .sample(random: random)
      end
      urls.each do |url|
        v = vars(facts: git.merge(remote_url: url))
        # Only the path-derived variables (CI_COMMIT_AUTHOR has an '@').
        leaked = v.select { |key, value| key.include?('PROJECT') && value.match?(%r{@|S.*S|pa/ss|p/w}) }
        expect(leaked).to be_empty, "#{url}: #{leaked}"
        expect(%w[group/proj proj]).to include(v['CI_PROJECT_PATH']), url
      end
    end

    it 'sets CI_DEFAULT_BRANCH and its slug, main when unknown' do
      expect(vars(facts: git.merge(default_branch: 'Release/2'))).to include(
        'CI_DEFAULT_BRANCH' => 'Release/2', 'CI_DEFAULT_BRANCH_SLUG' => 'release-2'
      )
      expect(vars(facts: {})).to include('CI_DEFAULT_BRANCH' => 'main')
    end

    it 'sets the commit variables like upstream Commit#full_title/#description' do
      expect(vars).to include(
        'CI_COMMIT_SHA' => sha, 'CI_COMMIT_SHORT_SHA' => 'aaaaaaaa',
        'CI_COMMIT_MESSAGE' => "Fix it\n\nbody line\n", 'CI_COMMIT_TITLE' => 'Fix it',
        'CI_COMMIT_DESCRIPTION' => "\nbody line", 'CI_COMMIT_MESSAGE_IS_TRUNCATED' => 'false',
        'CI_COMMIT_TIMESTAMP' => '1970-01-01T00:00:00Z', 'CI_COMMIT_AUTHOR' => 'A B <a@b>'
      )
    end

    it 'gives a one-line message an empty description and a blank one the placeholder title' do
      expect(vars(facts: git.merge(commit_message: "One line\n"))).to include('CI_COMMIT_DESCRIPTION' => '')
      expect(vars(facts: git.merge(commit_message: ''))).to include('CI_COMMIT_TITLE' => 'No commit message')
    end

    it 'truncates a commit message over 100000 bytes and says so' do
      long = "title\n#{'x' * 100_010}"
      v = vars(facts: git.merge(commit_message: long))
      expect(v['CI_COMMIT_MESSAGE'].bytesize).to eq(100_000)
      expect(v['CI_COMMIT_MESSAGE_IS_TRUNCATED']).to eq('true')
    end

    it 'leaves commit variables unset without a commit' do
      expect(vars(facts: {}).keys.grep(/\ACI_COMMIT_(SHA|SHORT_SHA|MESSAGE|TITLE|TIMESTAMP|AUTHOR)/)).to eq([])
    end
  end

  describe '.resolve_ref' do
    def resolve(ref, facts = {}, source: 'push')
      described_class.resolve_ref(ref, facts, source)
    end

    it 'uses the checked-out branch by default' do
      expect(resolve(nil, { head_branch: 'dev', head_tag: 'v1' }).to_h).to eq(kind: :branch, name: 'dev')
      expect(resolve('HEAD', { head_branch: 'dev' }).to_h).to eq(kind: :branch, name: 'dev')
    end

    it 'uses the one tag at a detached HEAD, and nothing otherwise' do
      expect(resolve(nil, { head_tag: 'v1' }).to_h).to eq(kind: :tag, name: 'v1')
      expect(resolve(nil, {})).to be_nil
    end

    it 'takes refs/heads/ and refs/tags/ literally' do
      expect(resolve('refs/heads/v1', { ref_is_tag: true }).to_h).to eq(kind: :branch, name: 'v1')
      expect(resolve('refs/tags/main').to_h).to eq(kind: :tag, name: 'main')
    end

    it 'makes a plain name a tag only if that tag exists, else a branch' do
      expect(resolve('v1', { ref_is_tag: true }).to_h).to eq(kind: :tag, name: 'v1')
      expect(resolve('feature-x', {}).to_h).to eq(kind: :branch, name: 'feature-x')
    end

    it 'rejects a name that is both a branch and a tag, as upstream' do
      expect { resolve('x', { ref_is_tag: true, ref_is_branch: true }) }
        .to raise_error(described_class::RefError, /Ref is ambiguous/)
    end

    it 'rejects an MR pipeline for a tag or an unknown ref' do
      expect { resolve('refs/tags/v1', source: 'merge_request_event') }
        .to raise_error(described_class::RefError, /is a tag/)
      expect { resolve(nil, {}, source: 'merge_request_event') }
        .to raise_error(described_class::RefError, /pass --ref BRANCH/)
    end
  end

  describe '.project_path_from_remote' do
    {
      'git@gitlab.com:group/proj.git' => 'group/proj',
      'gitlab.com:group/sub/proj' => 'group/sub/proj',
      'https://gitlab.com/group/sub/proj.git' => 'group/sub/proj',
      'https://user:token@gitlab.example.com/group/proj.git/' => 'group/proj',
      'ssh://git@gitlab.example.com:2222/group/proj.git' => 'group/proj',
      'https://gitlab.com/proj.git' => nil,
      '/srv/git/proj.git' => nil,
      '../proj' => nil,
      'file:///srv/git/group/proj.git' => nil,
      '' => nil,
      nil => nil
    }.each do |url, expected|
      it "#{url.inspect} -> #{expected.inspect}" do
        expect(described_class.project_path_from_remote(url)).to eq(expected)
      end
    end

    # Malformed URLs whose userinfo the URL regexes cannot strip: no part
    # of the secret may reach the path; the caller then falls back to the
    # directory name (pipeline_variables spec below).
    [
      'https://u:p/w@gitlab.example.com/group/proj.git', # '/' unencoded in the password
      'https://u:p/w/x@gitlab.example.com/group/proj',
      'https://u@x:p/w@gitlab.example.com/group/proj',   # '@' unencoded in the user
      'u:pa/ss@gitlab.example.com:group/proj.git',        # scp-like with '/' in the password
      'ssh://git@host/group/proj@secret',
      'https://gitlab.example.com/group/proj?private_token=secret',
      'https://gitlab.example.com/group/proj#secret',
      'https://gitlab.example.com/group/pro%20j',
      'https://gitlab.example.com/group//proj',
      "https://gitlab.example.com/group/proj\nsecret"
    ].each do |url|
      it "#{url.inspect} -> nil (no userinfo, query or junk in the path)" do
        expect(described_class.project_path_from_remote(url)).to be_nil
      end
    end
  end

  describe '.job_variables' do
    it 'sets name, slug, group name and stage' do
      expect(described_class.job_variables(name: 'Build: [aws, x86]', stage: 'build', when_value: nil)).to eq(
        'CI_JOB_NAME' => 'Build: [aws, x86]', 'CI_JOB_NAME_SLUG' => 'build---aws--x86',
        'CI_JOB_GROUP_NAME' => 'Build', 'CI_JOB_STAGE' => 'build', 'CI_NODE_TOTAL' => '1'
      )
    end

    it 'sets CI_NODE_TOTAL for every job and CI_NODE_INDEX only for a parallel instance' do
      expect(described_class.job_variables(name: 'j 2/3', stage: 's', when_value: nil, node_index: 2, node_total: 3))
        .to include('CI_NODE_INDEX' => '2', 'CI_NODE_TOTAL' => '3')
      expect(described_class.job_variables(name: 'j', stage: 's', when_value: nil)).not_to have_key('CI_NODE_INDEX')
    end

    it 'rejects a node_total below 1 (programmer error)' do
      expect { described_class.job_variables(name: 'j', stage: 's', when_value: nil, node_total: 0) }
        .to raise_error(ArgumentError, /node_total/)
    end

    it 'strips the parallel suffix from the group name' do
      expect(described_class.group_name('rspec 1/3')).to eq('rspec')
      expect(described_class.group_name('rspec')).to eq('rspec')
    end

    it 'sets CI_JOB_MANUAL only for manual and delayed jobs' do
      expect(described_class.job_variables(name: 'j', stage: 's', when_value: 'manual')).to include('CI_JOB_MANUAL' => 'true')
      expect(described_class.job_variables(name: 'j', stage: 's', when_value: 'delayed')).to include('CI_JOB_MANUAL' => 'true')
      expect(described_class.job_variables(name: 'j', stage: 's', when_value: 'on_success')).not_to have_key('CI_JOB_MANUAL')
    end
  end

  describe '.slugify' do
    it 'lowercases, dashes every non-alphanumeric, trims dashes, truncates to 63' do
      expect(described_class.slugify('Feature/My-Branch.1')).to eq('feature-my-branch-1')
      expect(described_class.slugify('---foo---')).to eq('foo')
      expect(described_class.slugify('a' * 100).length).to eq(63)
      expect(described_class.slugify('')).to eq('')
    end
  end

  describe '.build on a real checkout' do
    def git!(dir, *args)
      _out, err, status = Open3.capture3('git', '-C', dir, *args)
      raise "git #{args.join(' ')}: #{err}" unless status.success?
    end

    around do |example|
      Dir.mktmpdir('predefined_vars') do |dir|
        @dir = dir
        git!(dir, 'init', '-q', '-b', 'trunk')
        git!(dir, 'config', 'user.email', 't@example.com')
        git!(dir, 'config', 'user.name', 'T User')
        git!(dir, 'config', 'commit.gpgsign', 'false')
        git!(dir, 'config', 'tag.gpgsign', 'false')
        File.write(File.join(dir, 'f'), 'x')
        git!(dir, 'add', '.')
        git!(dir, 'commit', '-q', '-m', "Subject\n\nBody")
        example.run
      end
    end

    it 'derives a branch pipeline from the checked-out branch' do
      v = described_class.build(project_dir: @dir)
      expect(v).to include('CI_COMMIT_BRANCH' => 'trunk', 'CI_COMMIT_REF_NAME' => 'trunk',
                           'CI_COMMIT_TITLE' => 'Subject', 'CI_COMMIT_AUTHOR' => 'T User <t@example.com>')
      expect(v['CI_COMMIT_SHA']).to match(/\A\h{40}\z/)
      expect(v).not_to have_key('CI_COMMIT_TAG')
    end

    it 'derives a tag pipeline from a detached HEAD at one tag, and --ref NAME of a local tag' do
      git!(@dir, 'tag', 'v9')
      expect(described_class.build(project_dir: @dir, ref: 'v9')).to include('CI_COMMIT_TAG' => 'v9')
      git!(@dir, 'checkout', '-q', '--detach')
      v = described_class.build(project_dir: @dir)
      expect(v).to include('CI_COMMIT_TAG' => 'v9')
      expect(v).not_to have_key('CI_COMMIT_BRANCH')
    end

    it 'treats --ref of an unknown name as a (new) branch at HEAD' do
      v = described_class.build(project_dir: @dir, ref: 'feature-x')
      expect(v).to include('CI_COMMIT_BRANCH' => 'feature-x', 'CI_COMMIT_REF_SLUG' => 'feature-x')
    end

    it 'reports a name that is both a branch and a tag' do
      git!(@dir, 'tag', 'trunk')
      expect { described_class.build(project_dir: @dir, ref: 'trunk') }
        .to raise_error(described_class::RefError, /ambiguous/)
    end

    it 'reads the project path and default branch from origin' do
      git!(@dir, 'remote', 'add', 'origin', 'https://gitlab.example.com/grp/proj.git')
      git!(@dir, 'update-ref', 'refs/remotes/origin/trunk', 'HEAD')
      git!(@dir, 'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/trunk')
      expect(described_class.build(project_dir: @dir)).to include(
        'CI_PROJECT_PATH' => 'grp/proj', 'CI_DEFAULT_BRANCH' => 'trunk'
      )
    end

    it 'leaves ref and commit variables unset outside a git repository' do
      Dir.mktmpdir do |plain|
        v = described_class.build(project_dir: plain)
        expect(v.keys.grep(/\ACI_COMMIT_/)).to eq([])
        expect(v['CI_PROJECT_PATH']).to eq(File.basename(plain))
      end
    end
  end

  # AC#3 drift detectors against the gitlab/ submodule.
  describe 'against upstream' do
    let(:doc) { File.expand_path('../../gitlab/doc/ci/variables/predefined_variables.md', __dir__) }
    let(:enum) { File.expand_path('../../gitlab/app/models/concerns/enums/ci/pipeline.rb', __dir__) }

    it 'emits only variables documented in predefined_variables.md' do
      skip 'gitlab/ submodule not checked out' unless File.exist?(doc)

      documented = File.read(doc).scan(/^\| `([A-Z][A-Z0-9_]+)`/).flatten
      expect(documented.size).to be > 100, 'variable table not found; update this parser'
      emitted = [vars, vars(ref: tag), vars(source: 'merge_request_event'),
                 described_class.job_variables(name: 'j', stage: 's', when_value: 'manual')].flat_map(&:keys).uniq
      expect(emitted - documented).to eq([])
    end

    it 'accepts exactly upstream Enums::Ci::Pipeline.sources' do
      skip 'gitlab/ submodule not checked out' unless File.exist?(enum)

      body = File.read(enum)[/def self\.sources\s*\{(.*?)\}/m, 1]
      expect(body).not_to be_nil, 'sources not found; update this parser'
      expect(described_class::SOURCES.sort).to eq(body.scan(/^\s*(\w+):/).flatten.sort - %w[unknown])
    end
  end
end
