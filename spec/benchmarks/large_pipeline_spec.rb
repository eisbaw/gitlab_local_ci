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
require 'mock_server'
require 'benchmark'

RSpec.describe 'Large Pipeline Performance', type: :benchmark do
  let(:mock_server) { MockServer.new }

  # Helper to generate a large pipeline configuration
  def generate_pipeline_config(job_count:, stages: ['build', 'test', 'deploy'])
    config = { 'stages' => stages }

    jobs_per_stage = job_count / stages.length

    stages.each_with_index do |stage, stage_idx|
      job_start = stage_idx * jobs_per_stage
      job_end = stage_idx == stages.length - 1 ? job_count : (stage_idx + 1) * jobs_per_stage

      (job_start...job_end).each do |i|
        config["job_#{i}"] = {
          'stage' => stage,
          'script' => ["echo 'Running job #{i}'", "sleep 0.1"],
          'tags' => ['docker']
        }
      end
    end

    config
  end

  describe 'pipeline creation performance' do
    it 'creates 100-job pipeline in reasonable time' do
      config = generate_pipeline_config(job_count: 100, stages: ['build', 'test', 'deploy'])

      elapsed_time = Benchmark.realtime do
        mock_server.create_pipeline(config)
      end

      puts "  Created 100-job pipeline in #{(elapsed_time * 1000).round(2)}ms"
      expect(elapsed_time).to be < 1.0  # Should complete in under 1 second
    end

    it 'creates 1000-job pipeline in reasonable time' do
      config = generate_pipeline_config(job_count: 1000, stages: ['build', 'test', 'deploy', 'review', 'staging', 'production'])

      elapsed_time = Benchmark.realtime do
        mock_server.create_pipeline(config)
      end

      puts "  Created 1000-job pipeline in #{(elapsed_time * 1000).round(2)}ms"
      expect(elapsed_time).to be < 5.0  # Should complete in under 5 seconds
    end
  end

  describe 'pipeline processing performance' do
    it 'processes 100-job pipeline efficiently' do
      config = generate_pipeline_config(job_count: 100)
      pipeline = mock_server.create_pipeline(config)

      process_count = 0
      elapsed_time = Benchmark.realtime do
        while mock_server.has_pending_jobs?(pipeline) && process_count < 200
          mock_server.process_pipeline(pipeline)
          process_count += 1
        end
      end

      puts "  Processed 100-job pipeline in #{(elapsed_time * 1000).round(2)}ms (#{process_count} iterations)"
      expect(elapsed_time).to be < 2.0
    end
  end

  describe 'DAG performance with dependencies' do
    it 'handles complex dependency graph efficiently' do
      # Create a pipeline with complex needs relationships
      config = {
        'stages' => ['build', 'test', 'deploy'],
        'build_a' => {
          'stage' => 'build',
          'script' => ['echo build_a']
        },
        'build_b' => {
          'stage' => 'build',
          'script' => ['echo build_b']
        },
        'build_c' => {
          'stage' => 'build',
          'script' => ['echo build_c']
        }
      }

      # Add 50 test jobs that depend on build jobs
      (0...50).each do |i|
        needs = case i % 3
                when 0 then ['build_a']
                when 1 then ['build_b']
                else ['build_c']
                end

        config["test_#{i}"] = {
          'stage' => 'test',
          'script' => ["echo test_#{i}"],
          'needs' => needs
        }
      end

      # Add deploy jobs that depend on test jobs
      (0...10).each do |i|
        config["deploy_#{i}"] = {
          'stage' => 'deploy',
          'script' => ["echo deploy_#{i}"],
          'needs' => ["test_#{i * 5}", "test_#{i * 5 + 1}"]
        }
      end

      elapsed_time = Benchmark.realtime do
        mock_server.create_pipeline(config)
      end

      puts "  Created complex DAG pipeline in #{(elapsed_time * 1000).round(2)}ms"
      expect(elapsed_time).to be < 1.0
    end
  end

  describe 'memory usage' do
    it 'maintains reasonable memory footprint for large pipelines' do
      # This is a simple check - in production you'd use memory_profiler gem
      before_memory = `ps -o rss= -p #{Process.pid}`.to_i

      # Create multiple large pipelines
      5.times do |i|
        config = generate_pipeline_config(job_count: 200, stages: ['build', 'test'])
        mock_server.create_pipeline(config)
      end

      after_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_growth_mb = (after_memory - before_memory) / 1024.0

      puts "  Memory growth for 5x200-job pipelines: #{memory_growth_mb.round(2)} MB"
      expect(memory_growth_mb).to be < 100  # Should not grow more than 100MB
    end
  end

  describe 'concurrent pipeline handling' do
    it 'handles multiple pipelines efficiently' do
      pipelines = []

      elapsed_time = Benchmark.realtime do
        10.times do
          config = generate_pipeline_config(job_count: 50)
          pipelines << mock_server.create_pipeline(config)
        end
      end

      puts "  Created 10 pipelines (50 jobs each) in #{(elapsed_time * 1000).round(2)}ms"
      expect(elapsed_time).to be < 2.0
      expect(pipelines.length).to eq(10)
    end
  end
end
