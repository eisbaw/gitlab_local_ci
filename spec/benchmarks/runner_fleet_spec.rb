# frozen_string_literal: true

require 'spec_helper'
require 'runner_fleet'
require 'mock_runner'
require 'mock_job'
require 'tmpdir'
require 'benchmark'

RSpec.describe 'Runner Fleet Performance', type: :benchmark do
  # Helper to generate runner configurations
  def generate_runner_configs(count:, executor: 'docker', tags: ['linux'])
    runners = []

    count.times do |i|
      runners << {
        'id' => "runner_#{i}",
        'description' => "Runner #{i}",
        'executor' => executor,
        'tags' => tags + ["runner#{i}"],
        'max_jobs' => 1,
        'run_untagged' => false,
        'locked' => false
      }
    end

    runners
  end

  # Helper to create a runner fleet with JSON files
  def create_fleet_with_files(runner_count:, tmpdir:)
    runner_configs = generate_runner_configs(count: runner_count)

    runner_configs.each_with_index do |config, i|
      file_path = File.join(tmpdir, "runner_#{i}.json")
      File.write(file_path, JSON.pretty_generate(config))
    end

    fleet = RunnerFleet.new
    fleet.load_runners(tmpdir)
    fleet
  end

  # Helper to create jobs with different tag requirements
  def generate_jobs(count:, tag_distribution: { 'linux' => 0.7, 'docker' => 0.2, 'kubernetes' => 0.1 })
    jobs = []

    count.times do |i|
      tag_type = case (i.to_f / count)
                 when 0.0...tag_distribution['linux']
                   ['linux']
                 when tag_distribution['linux']...(tag_distribution['linux'] + tag_distribution['docker'])
                   ['docker']
                 else
                   ['kubernetes']
                 end

      jobs << MockJob.new(
        id: i,
        name: "job_#{i}",
        stage: 'test',
        script: ['echo test'],
        tag_list: tag_type
      )
    end

    jobs
  end

  describe 'runner loading performance' do
    it 'loads 10 runners quickly' do
      Dir.mktmpdir do |tmpdir|
        runner_configs = generate_runner_configs(count: 10)

        runner_configs.each_with_index do |config, i|
          file_path = File.join(tmpdir, "runner_#{i}.json")
          File.write(file_path, JSON.pretty_generate(config))
        end

        fleet = RunnerFleet.new

        elapsed_time = Benchmark.realtime do
          fleet.load_runners(tmpdir)
        end

        puts "  Loaded 10 runners in #{(elapsed_time * 1000).round(2)}ms"
        expect(elapsed_time).to be < 0.1
        expect(fleet.runners.count).to eq(10)
      end
    end

    it 'loads 100 runners efficiently' do
      Dir.mktmpdir do |tmpdir|
        runner_configs = generate_runner_configs(count: 100)

        runner_configs.each_with_index do |config, i|
          file_path = File.join(tmpdir, "runner_#{i}.json")
          File.write(file_path, JSON.pretty_generate(config))
        end

        fleet = RunnerFleet.new

        elapsed_time = Benchmark.realtime do
          fleet.load_runners(tmpdir)
        end

        puts "  Loaded 100 runners in #{(elapsed_time * 1000).round(2)}ms"
        expect(elapsed_time).to be < 0.5
        expect(fleet.runners.count).to eq(100)
      end
    end
  end

  describe 'runner matching performance' do
    it 'finds matching runner quickly in fleet of 10' do
      Dir.mktmpdir do |tmpdir|
        fleet = create_fleet_with_files(runner_count: 10, tmpdir: tmpdir)

        job = MockJob.new(
          id: 1,
          name: 'test_job',
          stage: 'test',
          script: ['echo test'],
          tag_list: ['linux']
        )

        elapsed_time = Benchmark.realtime do
          1000.times do
            fleet.find_available_runner(job)
          end
        end

        avg_time_ms = (elapsed_time / 1000) * 1000
        puts "  Average find time (10 runners): #{avg_time_ms.round(4)}ms"
        expect(elapsed_time).to be < 0.1  # 1000 lookups in < 100ms
      end
    end

    it 'finds matching runner efficiently in fleet of 100' do
      Dir.mktmpdir do |tmpdir|
        fleet = create_fleet_with_files(runner_count: 100, tmpdir: tmpdir)

        job = MockJob.new(
          id: 1,
          name: 'test_job',
          stage: 'test',
          script: ['echo test'],
          tag_list: ['linux']
        )

        elapsed_time = Benchmark.realtime do
          1000.times do
            fleet.find_available_runner(job)
          end
        end

        avg_time_ms = (elapsed_time / 1000) * 1000
        puts "  Average find time (100 runners): #{avg_time_ms.round(4)}ms"
        expect(elapsed_time).to be < 0.5  # 1000 lookups in < 500ms
      end
    end

    it 'handles worst-case scenario (no matching runner)' do
      Dir.mktmpdir do |tmpdir|
        # Create fleet with specific tags
        fleet = create_fleet_with_files(runner_count: 50, tmpdir: tmpdir)

        # Create job with tags that don't match any runner
        job = MockJob.new(
          id: 1,
          name: 'test_job',
          stage: 'test',
          script: ['echo test'],
          tag_list: ['nonexistent-tag']
        )

        elapsed_time = Benchmark.realtime do
          500.times do
            result = fleet.find_available_runner(job)
            expect(result).to be_nil
          end
        end

        avg_time_ms = (elapsed_time / 500) * 1000
        puts "  Average worst-case find time (50 runners): #{avg_time_ms.round(4)}ms"
        expect(elapsed_time).to be < 0.5
      end
    end
  end

  describe 'tag matching optimization' do
    it 'performs efficient tag intersection checks' do
      Dir.mktmpdir do |tmpdir|
        # Create runners with varied tag sets
        runner_configs = []
        100.times do |i|
          tags = ['linux']
          tags << 'docker' if i % 2 == 0
          tags << 'kubernetes' if i % 3 == 0
          tags << 'gpu' if i % 5 == 0
          tags << "zone-#{i % 10}"

          runner_configs << {
            'id' => "runner_#{i}",
            'executor' => 'docker',
            'tags' => tags,
            'max_jobs' => 1,
            'run_untagged' => false
          }
        end

        runner_configs.each_with_index do |config, i|
          File.write(File.join(tmpdir, "runner_#{i}.json"), JSON.pretty_generate(config))
        end

        fleet = RunnerFleet.new
        fleet.load_runners(tmpdir)

        # Create jobs with different tag requirements
        jobs = [
          MockJob.new(id: 1, name: 'job1', stage: 'test', script: ['echo'], tag_list: ['linux']),
          MockJob.new(id: 2, name: 'job2', stage: 'test', script: ['echo'], tag_list: ['linux', 'docker']),
          MockJob.new(id: 3, name: 'job3', stage: 'test', script: ['echo'], tag_list: ['linux', 'gpu']),
          MockJob.new(id: 4, name: 'job4', stage: 'test', script: ['echo'], tag_list: ['linux', 'kubernetes', 'zone-5'])
        ]

        elapsed_time = Benchmark.realtime do
          500.times do
            jobs.each do |job|
              fleet.find_available_runner(job)
            end
          end
        end

        total_lookups = 500 * jobs.length
        avg_time_ms = (elapsed_time / total_lookups) * 1000
        puts "  Average tag matching time: #{avg_time_ms.round(4)}ms (#{total_lookups} lookups)"
        expect(elapsed_time).to be < 2.0
      end
    end
  end

  describe 'capacity checking performance' do
    it 'efficiently checks runner capacity' do
      Dir.mktmpdir do |tmpdir|
        fleet = create_fleet_with_files(runner_count: 50, tmpdir: tmpdir)

        job = MockJob.new(
          id: 1,
          name: 'test_job',
          stage: 'test',
          script: ['echo test'],
          tag_list: ['linux']
        )

        # Assign jobs to some runners to vary capacity
        fleet.runners.first(25).each_with_index do |runner, i|
          runner.assign_job(MockJob.new(id: i + 100, name: "assigned_#{i}", stage: 'test', script: ['echo']))
        end

        elapsed_time = Benchmark.realtime do
          1000.times do
            fleet.find_available_runner(job)
          end
        end

        avg_time_ms = (elapsed_time / 1000) * 1000
        puts "  Average capacity check time: #{avg_time_ms.round(4)}ms"
        expect(elapsed_time).to be < 0.3
      end
    end
  end

  describe 'job assignment throughput' do
    it 'handles high job assignment rate' do
      Dir.mktmpdir do |tmpdir|
        fleet = create_fleet_with_files(runner_count: 100, tmpdir: tmpdir)
        jobs = generate_jobs(count: 500)

        assigned_count = 0

        elapsed_time = Benchmark.realtime do
          jobs.each do |job|
            runner = fleet.find_available_runner(job)
            if runner
              runner.assign_job(job)
              assigned_count += 1
            end
          end
        end

        rate = assigned_count / elapsed_time
        puts "  Job assignment rate: #{rate.round(2)} jobs/sec (#{assigned_count}/#{jobs.length} assigned)"
        expect(rate).to be > 100  # Should handle at least 100 assignments per second
      end
    end
  end
end
