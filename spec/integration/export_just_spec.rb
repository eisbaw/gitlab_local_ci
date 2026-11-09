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
require 'tmpdir'
require 'yaml'
require 'json'

# export-just writes recipes that behave like `run` (TASK-51, TASK-23).
# The generated recipes are executed with `just` (from the dev shell);
# scripts here only echo, export, cd and exit.
RSpec.describe 'export-just', type: :integration do
  let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }

  around do |example|
    Dir.mktmpdir('export_just_spec') do |dir|
      @project_dir = File.realpath(dir)
      example.run
    end
  end

  def justfile_path
    File.join(@project_dir, 'justfile.gitlab')
  end

  def export(yaml, *args)
    File.write(File.join(@project_dir, '.gitlab-ci.yml'), yaml)
    _stdout, stderr, status = Open3.capture3(bin_path, 'export-just', *PinnedPipelineContext::CLI_ARGS, *args,
                                             '--entry', File.join(@project_dir, '.gitlab-ci.yml'),
                                             '--output', justfile_path)
    raise "export-just failed (#{status.exitstatus}): #{stderr}" unless status.success?

    File.read(justfile_path)
  end

  # From `/`, so the recipe's cwd cannot be the caller's by accident.
  def just(*args)
    stdout, stderr, status = Open3.capture3('just', '--justfile', justfile_path, *args, chdir: '/')
    [stdout, stderr, status.exitstatus]
  end

  it 'writes a justfile just accepts for multi-line entries, heredocs and {{' do
    export(<<~YAML)
      job:
        script:
          - |
            cat <<EOF
            <?xml version="1.0"?>
              {{ not.a.just.expression }}
            EOF
          - echo '{{x}}'
    YAML
    _stdout, stderr, status = just('--evaluate')
    expect(status).to eq(0), stderr
    stdout, stderr, status = just('job')
    expect(status).to eq(0), stderr
    expect(stdout).to eq("<?xml version=\"1.0\"?>\n  {{ not.a.just.expression }}\n{{x}}\n")
  end

  it 'runs the job like `run`: variables exported, one shell, project dir, pipefail' do
    export(<<~YAML, '--variables', "CLIVAR=it's")
      variables:
        GLOBAL: global
      job:
        variables:
          JOBVAR: "j-$GLOBAL"
        before_script:
          - echo "start=$(pwd)"
          - export CARRIED=yes
          - cd /
        script:
          - echo "GLOBAL=[$GLOBAL] JOBVAR=[$JOBVAR] CLIVAR=[$CLIVAR] NAME=[$CI_JOB_NAME] carried=[$CARRIED] now=$(pwd)"
          - echo 'quoted [$CLIVAR]'
          - false | true
          - echo not-reached
    YAML
    stdout, _stderr, status = just('job')
    expect(status).to eq(1)
    expect(stdout).to include("start=#{@project_dir}",
                              "GLOBAL=[global] JOBVAR=[j-global] CLIVAR=[it's] NAME=[job] carried=[yes] now=/",
                              'quoted [$CLIVAR]')
    expect(stdout).not_to include('not-reached')
  end

  it 'runs after_script in a second shell, also after a failure, and keeps the exit code' do
    export(<<~YAML)
      job:
        script:
          - export IN_SCRIPT=leaked
          - exit 3
        after_script:
          - echo "after status=[$CI_JOB_STATUS] in_script=[$IN_SCRIPT] pwd=$(pwd)"
          - exit 9
    YAML
    stdout, stderr, status = just('job')
    expect(status).to eq(3)
    expect(stdout).to include("after status=[failed] in_script=[] pwd=#{@project_dir}")
    expect(stderr).to include('after_script failed or timed out (exit code 9); the job result is unchanged')
  end

  it 'makes graph recipes depend on what the job waits for, as dry-run schedules it' do
    justfile = export(<<~YAML, '--graph')
      stages: [build, test, deploy]
      build: {stage: build, script: [echo build]}
      unit: {stage: test, needs: [], script: [echo unit]}
      integration: {stage: test, needs: [build], script: [echo integration]}
      rescue: {stage: test, when: on_failure, script: [echo rescue]}
      deploy: {stage: deploy, script: [echo deploy]}
    YAML
    expect(justfile).to match(/^unit:$/)
    expect(justfile).to match(/^integration: build$/)
    expect(justfile).to match(/^deploy: build unit integration$/) # rescue: not on the success path
    _stdout, stderr, status = just('--evaluate')
    expect(status).to eq(0), stderr
  end

  it 'names parallel instances as just identifiers, keeps the real name in a comment, and runs them (TASK-18)' do
    justfile = export(<<~YAML)
      t:
        parallel: 2
        script: [echo "node=$CI_NODE_INDEX/$CI_NODE_TOTAL"]
      m:
        parallel: {matrix: [{P: [aws], A: [x86, arm/v7]}]}
        script: [echo "p=$P a=$A"]
    YAML
    expect(justfile).to include("# t 1/2\n", "\nt_1_2:\n", "# m: [aws, arm/v7]\n", "\nm_aws_arm_v7:\n")
    stdout, stderr, status = just('t_2_2')
    expect(status).to eq(0), stderr
    expect(stdout).to eq("node=2/2\n")
    stdout, stderr, status = just('m_aws_x86')
    expect(status).to eq(0), stderr
    expect(stdout).to eq("p=aws a=x86\n")
  end

  # Config text is untrusted: just evaluates top-level assignments (and
  # their backticks) whatever recipe runs, so text that escapes its comment
  # line runs code. Every sentinel lives in the per-example temp dir.
  describe 'config text cannot inject justfile syntax' do
    def sentinel
      File.join(@project_dir, 'pwned')
    end

    def recipe_list
      stdout, stderr, status = just('--list')
      raise "just --list failed: #{stderr}" unless status.zero?

      stdout.lines.drop(1).map { |line| line.split.first }
    end

    it 'keeps a job name with a newline from adding a recipe' do
      export(YAML.dump("evil\nboom:\n    touch #{sentinel}" => { 'script' => ['echo hi'] }))
      expect(recipe_list).to eq(["evil_boom_touch#{sentinel.gsub(/[^A-Za-z0-9_-]+/, '_')}"])
      _stdout, _stderr, status = just('boom')
      expect(status).not_to eq(0)
      expect(File.exist?(sentinel)).to be(false)
    end

    it 'keeps a tag with a newline from adding an assignment that runs with any recipe' do
      export(YAML.dump('harmless' => { 'script' => ['echo harmless'] },
                       'tagged' => { 'tags' => ["t\npwn := `touch #{sentinel}`"], 'script' => ['echo x'] }))
      stdout, stderr, status = just('harmless')
      expect(status).to eq(0), stderr
      expect(stdout).to eq("harmless\n")
      expect(File.exist?(sentinel)).to be(false)
    end

    it 'keeps --entry and --output paths with a newline inside the header comment' do
      # A file name cannot hold '/', so the payload reads the sentinel path
      # from the environment (unset: `touch ''` fails, touching nothing).
      env = { 'EXPORT_JUST_SENTINEL' => sentinel }
      dir = File.join(@project_dir, "d\npwn := `touch \"$EXPORT_JUST_SENTINEL\"`")
      Dir.mkdir(dir)
      entry = File.join(dir, '.gitlab-ci.yml')
      output = File.join(dir, "out\nalso := `touch \"$EXPORT_JUST_SENTINEL\"`")
      File.write(entry, "job: {script: [echo job]}\n")
      _stdout, stderr, status = Open3.capture3(bin_path, 'export-just', *PinnedPipelineContext::CLI_ARGS,
                                               '--entry', entry, '--output', output)
      expect(status.success?).to be(true), stderr
      stdout, stderr, status = Open3.capture3(env, 'just', '--justfile', output, 'job', chdir: '/')
      expect(status.success?).to be(true), stderr
      expect(stdout).to eq("job\n")
      expect(File.exist?(sentinel)).to be(false)
    end

    # Seeded random job names, stages, tags, environment names and variable
    # values made of the characters that end or open just syntax. Job names
    # start with a unique "j<i>z" so they never collide (collisions have
    # their own spec) and the expected recipe names follow from docs/usage.md
    # rule alone.
    it 'writes exactly one recipe per job and runs nothing at --list/--evaluate, for random hostile text' do
      seed = Integer(ENV.fetch('EXPORT_JUST_SEED', '20261110'))
      random = Random.new(seed)
      pieces = ["\n", "\r", "\r\n", "\u2028", "\t", '`', ':=', '{{', '}}', "'", '"', '#', '\\', ' ', ':', 'a', '7',
                'export', 'set', 'alias', "x := `touch #{sentinel}`", "$(touch #{sentinel})", "\nrec:\n    touch #{sentinel}"]
      junk = -> { Array.new(random.rand(1..6)) { pieces.sample(random: random) }.join }
      expected_name = lambda do |name|
        base = name.gsub(/[^A-Za-z0-9_-]+/, '_')
        name.match?(/[^A-Za-z0-9_-]\z/) && base.size > 1 ? base.delete_suffix('_') : base
      end

      6.times do |trial|
        stages = Array.new(3) { |i| "s#{i}#{junk.call}" }
        jobs = Array.new(random.rand(1..5)) do |i|
          ["j#{i}z#{junk.call}", {
            'stage' => stages.sample(random: random),
            'tags' => Array.new(random.rand(0..2)) { junk.call },
            'environment' => { 'name' => junk.call },
            'variables' => { 'HOSTILE' => junk.call },
            'script' => ["echo job-#{i}"]
          }]
        end.to_h
        context = "seed #{seed}, trial #{trial}: #{jobs.keys.inspect}"
        ['--graph', '--flat'].each do |mode|
          export(YAML.dump({ 'stages' => stages }.merge(jobs)), mode)
          expect(recipe_list.sort).to eq(jobs.keys.map(&expected_name).sort), "#{mode} #{context}"
          _stdout, stderr, status = just('--evaluate')
          expect(status).to eq(0), "#{mode} #{context}: #{stderr}"
          stdout, stderr, status = just(expected_name.call(jobs.keys.last))
          expect(status).to eq(0), "#{mode} #{context}: #{stderr}"
          expect(stdout).to include("job-#{jobs.size - 1}\n")
          expect(File.exist?(sentinel)).to be(false), "#{mode} #{context}"
        end
      end
    end
  end

  # The suffix is part of the recipe-name format (docs/usage.md): pinned here as
  # literals, the first 6 hex digits of SHA-256 of each job name.
  it 'gives every member of a recipe-name collision a suffix from its own job name' do
    justfile = export("'a b': {script: [echo 1]}\n'a/b': {script: [echo 2]}\n'a:b': {script: [echo 3]}\n" \
                      "'c d': {script: [echo 4]}\n")
    expect(justfile).to include("# a b\n", "\na_b_c8687a:\n", "# a/b\n", "\na_b_c14cdd:\n",
                                "# a:b\n", "\na_b_6783a3:\n", "\nc_d:\n")
    expect(justfile).not_to match(/^a_b:/)
    stdout, stderr, status = just('a_b_6783a3')
    expect(status).to eq(0), stderr
    expect(stdout).to eq("3\n")
  end

  # Behaviour, not text: every recipe is run and must echo its own job, in
  # every order of the same jobs (graph mode, so dependencies are named by
  # recipe too).
  it 'maps each recipe to the same job whatever the order of the jobs in the config' do
    jobs = { 'a b' => 'build', 'a/b' => 'build', 'a:b' => 'test', 'rspec 1/2' => 'test', 'rspec_1_2' => 'test',
             'solo' => 'test' }
    mappings = jobs.keys.permutation.to_a.values_at(0, 1, 119, 360, 719).map do |order|
      yaml = "stages: [build, test]\n" + order.map { |name| "#{name.to_json}: {stage: #{jobs[name]}, script: [echo #{name.to_json}]}\n" }.join
      export(yaml, '--flat')
      stdout, stderr, status = just('--summary')
      raise "just --summary: #{stderr}" unless status.zero?

      stdout.split.to_h do |recipe|
        out, err, code = just(recipe)
        raise "just #{recipe}: #{err}" unless code.zero?

        [recipe, out.chomp]
      end
    end
    expect(mappings.uniq.size).to eq(1), mappings.inspect
    expect(mappings.first.values.sort).to eq(jobs.keys.sort)
    expect(mappings.first.keys).to include('solo')
    expect(mappings.first.keys.grep(/\Aa_b_[0-9a-f]{6}\z/).size).to eq(3)
    expect(mappings.first.keys.grep(/\Arspec_1_2_[0-9a-f]{6}\z/).size).to eq(2)
  end

  it 'fails, naming the jobs, when a suffixed name equals another job name' do
    File.write(File.join(@project_dir, '.gitlab-ci.yml'),
               "'a b': {script: [echo 1]}\n'a/b': {script: [echo 2]}\na_b_c8687a: {script: [echo 3]}\n")
    _stdout, stderr, status = Open3.capture3(bin_path, 'export-just', *PinnedPipelineContext::CLI_ARGS,
                                             '--entry', File.join(@project_dir, '.gitlab-ci.yml'),
                                             '--output', justfile_path)
    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('recipe name a_b_c8687a would be shared by jobs "a b", "a_b_c8687a"; rename one')
  end

  it 'no longer accepts --shell' do
    File.write(File.join(@project_dir, '.gitlab-ci.yml'), "job: {script: [echo]}\n")
    _stdout, stderr, status = Open3.capture3(bin_path, 'export-just', '--shell', 'sh',
                                             '--entry', File.join(@project_dir, '.gitlab-ci.yml'))
    expect(status.exitstatus).not_to eq(0)
    expect(stderr).to include('Unknown flag: --shell')
  end
end
