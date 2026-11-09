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
require 'runner_fleet'
require 'mock_runner'
require 'mock_job'
require 'tmpdir'

RSpec.describe RunnerFleet do
  describe '#initialize' do
    it 'should initialize with an empty runners array' do
      fleet = described_class.new

      expect(fleet.runners).to be_an(Array)
      expect(fleet.runners).to be_empty
    end
  end

  describe '#load_runners' do
    let(:fleet) { described_class.new }
    let(:fixtures_dir) { File.join(fixtures_path, 'runners') }

    context 'implementation tests' do
      it 'should load runners from directory containing JSON files' do
        count = fleet.load_runners(fixtures_dir)

        expect(count).to be > 0
        expect(fleet.runners.size).to eq(count)
      end

      it 'should create MockRunner instances for each JSON file' do
        fleet.load_runners(fixtures_dir)

        expect(fleet.runners).to all(be_a(MockRunner))
      end

      it 'should return count of loaded runners' do
        count = fleet.load_runners(fixtures_dir)

        expect(count).to eq(fleet.runners.size)
      end

      xit 'should handle directory with no JSON files' do
        empty_dir = File.join(fixtures_path, 'empty')
        Dir.mkdir(empty_dir) unless Dir.exist?(empty_dir)

        count = fleet.load_runners(empty_dir)

        expect(count).to eq(0)
        expect(fleet.runners).to be_empty

        Dir.rmdir(empty_dir) if Dir.exist?(empty_dir) && Dir.empty?(empty_dir)
      end

      xit 'should handle non-existent directory' do
        expect do
          fleet.load_runners('/nonexistent/directory')
        end.to raise_error(ArgumentError, /directory does not exist/)
      end

      xit 'should handle directory path that is a file' do
        file_path = fixture_path('runners', 'docker_runner.json')

        expect do
          fleet.load_runners(file_path)
        end.to raise_error(ArgumentError, /not a directory/)
      end

      xit 'should skip invalid JSON files with warning' do
        # Assuming there's an invalid JSON file in test fixtures
        invalid_dir = File.join(fixtures_path, 'invalid_runners')

        expect do
          fleet.load_runners(invalid_dir)
        end.to output(/Skipping invalid JSON/).to_stderr
      end

      xit 'should skip JSON files with missing required fields' do
        # Test that runners with incomplete data are skipped
        incomplete_dir = File.join(fixtures_path, 'incomplete_runners')

        count = fleet.load_runners(incomplete_dir)

        # Should skip incomplete runners and only load valid ones
        expect(count).to be >= 0
      end

      xit 'should handle multiple runner files' do
        # Assuming fixtures contain multiple runner JSON files
        count = fleet.load_runners(fixtures_dir)

        expect(count).to be >= 1
      end

      xit 'should preserve existing runners when loading more' do
        initial_runner = MockRunner.new({ 'id' => 999, 'tags' => ['test'] })
        fleet.runners << initial_runner

        fleet.load_runners(fixtures_dir)

        expect(fleet.runners).to include(initial_runner)
        expect(fleet.runners.size).to be > 1
      end

      xit 'should handle runners with different executor types' do
        fleet.load_runners(fixtures_dir)

        executors = fleet.runners.map(&:executor).uniq
        expect(executors).not_to be_empty
      end
    end
  end

  describe '#find_available_runner' do
    let(:fleet) { described_class.new }
    let(:job_data) do
      {
        'id' => 1,
        'name' => 'test_job',
        'stage' => 'test',
        'script' => ['echo "test"'],
        'tags' => ['docker', 'linux']
      }
    end
    let(:job) { MockJob.new(job_data) }

    context 'implementation tests' do
      let(:runner1) do
        MockRunner.new({
          'id' => 1,
          'tags' => ['docker', 'linux'],
          'max_jobs' => 1
        })
      end

      let(:runner2) do
        MockRunner.new({
          'id' => 2,
          'tags' => ['shell', 'linux'],
          'max_jobs' => 2
        })
      end

      before do
        fleet.runners << runner1
        fleet.runners << runner2
      end

      xit 'should return runner that can handle job' do
        allow(runner1).to receive(:can_handle?).with(job).and_return(true)
        allow(runner1).to receive(:has_capacity?).and_return(true)
        allow(runner2).to receive(:can_handle?).with(job).and_return(false)

        runner = fleet.find_available_runner(job)

        expect(runner).to eq(runner1)
      end

      xit 'should check runner capacity' do
        allow(runner1).to receive(:can_handle?).with(job).and_return(true)
        allow(runner1).to receive(:has_capacity?).and_return(false)
        allow(runner2).to receive(:can_handle?).with(job).and_return(true)
        allow(runner2).to receive(:has_capacity?).and_return(true)

        runner = fleet.find_available_runner(job)

        expect(runner).to eq(runner2)
      end

      xit 'should return nil when no runner can handle job' do
        allow(runner1).to receive(:can_handle?).with(job).and_return(false)
        allow(runner2).to receive(:can_handle?).with(job).and_return(false)

        runner = fleet.find_available_runner(job)

        expect(runner).to be_nil
      end

      xit 'should return nil when all runners at capacity' do
        allow(runner1).to receive(:can_handle?).with(job).and_return(true)
        allow(runner1).to receive(:has_capacity?).and_return(false)
        allow(runner2).to receive(:can_handle?).with(job).and_return(true)
        allow(runner2).to receive(:has_capacity?).and_return(false)

        runner = fleet.find_available_runner(job)

        expect(runner).to be_nil
      end

      xit 'should return first available runner when multiple match' do
        allow(runner1).to receive(:can_handle?).with(job).and_return(true)
        allow(runner1).to receive(:has_capacity?).and_return(true)
        allow(runner2).to receive(:can_handle?).with(job).and_return(true)
        allow(runner2).to receive(:has_capacity?).and_return(true)

        runner = fleet.find_available_runner(job)

        expect(runner).to eq(runner1)
      end

      xit 'should handle empty runner fleet' do
        empty_fleet = described_class.new

        runner = empty_fleet.find_available_runner(job)

        expect(runner).to be_nil
      end

      xit 'should handle job with no tags' do
        untagged_job = MockJob.new(job_data.merge('tags' => []))

        runner = fleet.find_available_runner(untagged_job)

        # Should return runner with run_untagged capability
        expect(runner).to be_a(MockRunner).or be_nil
      end

      xit 'should handle job with tags not matching any runner' do
        special_job = MockJob.new(job_data.merge('tags' => ['gpu', 'cuda']))
        allow(runner1).to receive(:can_handle?).with(special_job).and_return(false)
        allow(runner2).to receive(:can_handle?).with(special_job).and_return(false)

        runner = fleet.find_available_runner(special_job)

        expect(runner).to be_nil
      end

      xit 'should check both tag compatibility and capacity' do
        # Ensure both conditions are checked
        expect(runner1).to receive(:can_handle?).with(job)
        expect(runner1).to receive(:has_capacity?)

        fleet.find_available_runner(job)
      end
    end
  end

  describe 'integration with MockRunner' do
    let(:fleet) { described_class.new }

    context 'when implemented' do
      xit 'should work with real MockRunner instances' do
        runner_data = load_runner_fixture('docker_runner.json')
        runner = MockRunner.new(runner_data)
        fleet.runners << runner

        job = MockJob.new({
          'id' => 1,
          'name' => 'test',
          'script' => ['echo test'],
          'tags' => ['docker']
        })

        # This tests the integration between RunnerFleet and MockRunner
        found = fleet.find_available_runner(job)

        expect(found).to eq(runner).or be_nil
      end
    end
  end

  describe 'edge cases' do
    let(:fleet) { described_class.new }

    context 'when implemented' do
      xit 'should handle concurrent modifications to runners array' do
        # This tests thread safety concerns
        threads = []

        10.times do |i|
          threads << Thread.new do
            runner = MockRunner.new({ 'id' => i, 'tags' => ['test'] })
            fleet.runners << runner
          end
        end

        threads.each(&:join)

        expect(fleet.runners.size).to eq(10)
      end

      xit 'should handle nil job' do
        expect do
          fleet.find_available_runner(nil)
        end.to raise_error(ArgumentError, /job cannot be nil/)
      end

      xit 'should handle runner array modifications during search' do
        # Ensure search handles concurrent modifications gracefully
        fleet.runners << MockRunner.new({ 'id' => 1, 'tags' => ['test'] })

        job = MockJob.new({
          'id' => 1,
          'name' => 'test',
          'script' => ['echo test'],
          'tags' => ['test']
        })

        # Modify runners during search (edge case)
        allow(fleet).to receive(:find_available_runner) do |j|
          fleet.runners.clear
          nil
        end

        expect do
          fleet.find_available_runner(job)
        end.not_to raise_error
      end
    end
  end

  # runners/*.json is a user-written input format (dry-run --runners), so
  # its validation is pinned by behaviour on real files, not stubs.
  describe 'runner file format' do
    let(:fleet) { described_class.new }
    let(:valid_runner) { { 'id' => 'r1', 'tags' => ['docker'], 'executor' => 'shell', 'max_jobs' => 2 } }

    around do |example|
      Dir.mktmpdir('runners') do |dir|
        @dir = dir
        example.run
      end
    end

    def write_runner(name, content)
      path = File.join(@dir, name)
      File.write(path, content.is_a?(String) ? content : JSON.generate(content))
      path
    end

    it 'loads every *.json file, accepting the tag_list/concurrent aliases, and ignores other files' do
      write_runner('a.json', valid_runner)
      write_runner('b.json', { 'id' => 7, 'tag_list' => [], 'executor' => 'docker', 'concurrent' => 4 })
      write_runner('notes.txt', 'not a runner')

      expect(fleet.load_runners(@dir)).to eq(2)
      expect(fleet.runners.map(&:id)).to eq(['r1', 7])
    end

    it 'rejects a missing directory and a path that is a file' do
      file = write_runner('a.json', valid_runner)

      expect { fleet.load_runners(File.join(@dir, 'nope')) }.to raise_error(ArgumentError, /directory does not exist/)
      # A file is rejected naming it; the message wrongly says "does not
      # exist" because Dir.exist? is false for files (TASK-46).
      expect { fleet.load_runners(file) }.to raise_error(ArgumentError, /#{Regexp.escape(file)}/)
    end

    it 'names the file when its JSON does not parse' do
      path = write_runner('broken.json', '{"id": ')

      expect { fleet.load_runners(@dir) }.to raise_error(ArgumentError, /Failed to parse JSON in runner file '#{Regexp.escape(path)}'/)
    end

    {
      'missing id' => [->(r) { r.delete('id') }, /missing required field 'id'/],
      'id of the wrong type' => [->(r) { r['id'] = 1.5 }, /field 'id' must be a string or integer, got Float/],
      'missing tags' => [->(r) { r.delete('tags') }, /missing required field 'tags' \(or 'tag_list'\)/],
      'tags not a list' => [->(r) { r['tags'] = 'docker' }, /field 'tags' \(or 'tag_list'\) must be an array, got String/],
      'missing executor' => [->(r) { r.delete('executor') }, /missing required field 'executor'/],
      'executor not a string' => [->(r) { r['executor'] = 3 }, /field 'executor' must be a string, got Integer/],
      'missing max_jobs' => [->(r) { r.delete('max_jobs') }, /missing required field 'max_jobs' \(or 'concurrent'\)/],
      'max_jobs zero' => [->(r) { r['max_jobs'] = 0 }, /must be a positive integer, got 0/],
      'max_jobs not an integer' => [->(r) { r['max_jobs'] = '2' }, /must be a positive integer, got "2"/]
    }.each do |case_name, (mutate, message)|
      it "rejects a runner with #{case_name}, naming the file, and loads none" do
        runner = valid_runner.dup
        mutate.call(runner)
        path = write_runner('bad.json', runner)

        expect { fleet.load_runners(@dir) }.to raise_error(ArgumentError) { |error|
          expect(error.message).to match(message)
          expect(error.message).to include(path)
        }
        expect(fleet.runners).to be_empty
      end
    end
  end

  describe '#find_available_runner with real runners' do
    let(:fleet) { described_class.new }
    let(:docker_one_slot) { MockRunner.new('id' => 'docker1', 'tags' => %w[docker linux], 'max_jobs' => 1) }
    let(:docker_two_slots) { MockRunner.new('id' => 'docker2', 'tags' => %w[docker], 'max_jobs' => 2) }
    let(:untagged_ok) { MockRunner.new('id' => 'any', 'tags' => %w[shell], 'max_jobs' => 1, 'run_untagged' => true) }

    def job(name, tags)
      MockJob.new('id' => name.hash, 'name' => name, 'stage' => 'test', 'script' => ['true'], 'tags' => tags)
    end

    before { fleet.runners.push(docker_one_slot, docker_two_slots, untagged_ok) }

    it 'picks the first runner, in load order, that has all the job tags and a free slot' do
      expect(fleet.find_available_runner(job('a', %w[docker linux]))).to be(docker_one_slot)
      expect(fleet.find_available_runner(job('b', %w[docker]))).to be(docker_one_slot)
    end

    it 'skips a matching runner that is full' do
      docker_one_slot.assign_job(job('busy', %w[docker]))

      expect(fleet.find_available_runner(job('b', %w[docker]))).to be(docker_two_slots)
    end

    it 'returns nil when matching runners are all full, and when no runner has the tags' do
      docker_one_slot.assign_job(job('x', %w[docker linux]))
      expect(fleet.find_available_runner(job('a', %w[docker linux]))).to be_nil
      expect(fleet.find_available_runner(job('gpu', %w[gpu]))).to be_nil
    end

    it 'gives an untagged job only to a runner with run_untagged' do
      expect(fleet.find_available_runner(job('plain', []))).to be(untagged_ok)
    end

    it 'fails fast on a nil job' do
      expect { fleet.find_available_runner(nil) }.to raise_error(ArgumentError, /job cannot be nil/)
    end
  end
end
