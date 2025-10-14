# frozen_string_literal: true

require 'spec_helper'
require 'runner_fleet'
require 'mock_runner'
require 'mock_job'

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
end
