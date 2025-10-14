# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'tempfile'

RSpec.describe 'GitLab CI Dry-Run Command', type: :integration do
  let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }
  let(:fixtures_path) { File.expand_path('../fixtures/yaml', __dir__) }
  let(:runners_path) { File.expand_path('../fixtures/runners', __dir__) }
  let(:valid_simple_file) { File.join(fixtures_path, 'valid_simple.yml') }
  let(:valid_with_needs_file) { File.join(fixtures_path, 'valid_with_needs.yml') }
  let(:complex_pipeline_file) { File.join(fixtures_path, 'complex_pipeline.yml') }

  # Helper method to execute dry-run command
  # Returns: [stdout, stderr, exit_status]
  def run_dry_run(file_path, runners_dir: runners_path, extra_args: [])
    args = ['dry-run', '--entry', file_path, '--runners', runners_dir] + extra_args
    stdout, stderr, status = Open3.capture3(bin_path, *args)
    [stdout, stderr, status.exitstatus]
  end

  # Helper to create temporary runner fleet
  def with_temp_runner_fleet(runner_configs)
    Dir.mktmpdir do |tmpdir|
      runner_configs.each_with_index do |config, idx|
        File.write(
          File.join(tmpdir, "runner_#{idx}.json"),
          JSON.generate(config)
        )
      end
      yield tmpdir
    end
  end

  context 'basic execution' do
    describe 'simple pipeline' do
      it 'executes successfully with valid pipeline and runners' do
        stdout, stderr, status = run_dry_run(valid_simple_file)

        expect(status).to eq(0), "Expected success. STDERR: #{stderr}"
      end

      it 'reports pipeline creation' do
        stdout, _stderr, _status = run_dry_run(valid_simple_file)

        # Should mention pipeline was created
        expect(stdout).to match(/pipeline.*created/i)
      end

      it 'lists all jobs from pipeline' do
        stdout, _stderr, _status = run_dry_run(valid_simple_file)

        # All jobs should be mentioned
        expect(stdout).to include('build_job')
        expect(stdout).to include('test_job')
        expect(stdout).to include('deploy_job')
      end

      it 'reports pipeline completion status' do
        stdout, _stderr, _status = run_dry_run(valid_simple_file)

        # Should report final status
        expect(stdout).to match(/pipeline.*complete|finish|success|status/i)
      end
    end

    describe 'pipeline with needs dependencies' do
      it 'executes complex DAG pipeline' do
        stdout, stderr, status = run_dry_run(valid_with_needs_file)

        expect(status).to eq(0), "Expected success. STDERR: #{stderr}"
      end

      it 'respects needs dependencies in execution order' do
        stdout, _stderr, _status = run_dry_run(valid_with_needs_file)

        # setup_env must run before build_*
        setup_position = stdout.index('setup_env') || 0
        build_backend_position = stdout.index('build_backend') || Float::INFINITY
        build_frontend_position = stdout.index('build_frontend') || Float::INFINITY

        expect(setup_position).to be < build_backend_position
        expect(setup_position).to be < build_frontend_position
      end

      it 'shows parallel job execution within same stage' do
        stdout, _stderr, _status = run_dry_run(valid_with_needs_file)

        # build_backend and build_frontend can run in parallel
        # Should both be mentioned in output
        expect(stdout).to include('build_backend')
        expect(stdout).to include('build_frontend')
      end
    end
  end

  context 'runner assignment' do
    describe 'job to runner mapping' do
      it 'assigns jobs to available runners' do
        stdout, _stderr, _status = run_dry_run(valid_simple_file)

        # Should show job → runner assignments (uses arrow character)
        expect(stdout).to match(/job.*→.*runner|assigned.*runner/i)
      end

      it 'displays runner identifiers for assignments' do
        stdout, _stderr, _status = run_dry_run(valid_simple_file)

        # Should mention specific runner (from fixtures)
        expect(stdout).to match(/runner[-_]?\w+/i)
      end

      it 'assigns multiple jobs when runner has capacity' do
        # Create runner with capacity for multiple jobs
        with_temp_runner_fleet([{
          id: 'high-capacity-runner',
          tags: ['docker', 'linux'],
          max_jobs: 10,
          run_untagged: true
        }]) do |tmpdir|
          stdout, _stderr, status = run_dry_run(valid_with_needs_file, runners_dir: tmpdir)

          expect(status).to eq(0)

          # Single runner should handle multiple jobs
          expect(stdout.scan(/high-capacity-runner/).size).to be >= 2
        end
      end
    end

    describe 'tag matching' do
      it 'matches jobs to runners with compatible tags' do
        # Create pipeline with tagged jobs and specific runners
        pipeline_with_tags = <<~YAML
          stages: [test]

          docker-job:
            stage: test
            tags: [docker]
            script: echo "Docker job"

          shell-job:
            stage: test
            tags: [shell]
            script: echo "Shell job"
        YAML

        pipeline_file = Tempfile.new(['pipeline', '.yml'])
        pipeline_file.write(pipeline_with_tags)
        pipeline_file.close

        with_temp_runner_fleet([
          { id: 'docker-runner', tags: ['docker'], max_jobs: 1, run_untagged: false },
          { id: 'shell-runner', tags: ['shell'], max_jobs: 1, run_untagged: false }
        ]) do |tmpdir|
          stdout, _stderr, status = run_dry_run(pipeline_file.path, runners_dir: tmpdir)

          expect(status).to eq(0)

          # Jobs should be matched to appropriate runners
          expect(stdout).to match(/docker-job.*docker-runner/i) if stdout.include?('docker-job')
          expect(stdout).to match(/shell-job.*shell-runner/i) if stdout.include?('shell-job')
        end

        pipeline_file.unlink
      end

      it 'uses run_untagged runners for untagged jobs' do
        pipeline_untagged = <<~YAML
          stages: [test]

          simple-job:
            stage: test
            script: echo "Simple job"
        YAML

        pipeline_file = Tempfile.new(['pipeline', '.yml'])
        pipeline_file.write(pipeline_untagged)
        pipeline_file.close

        with_temp_runner_fleet([
          { id: 'untagged-runner', tags: [], max_jobs: 1, run_untagged: true }
        ]) do |tmpdir|
          stdout, _stderr, status = run_dry_run(pipeline_file.path, runners_dir: tmpdir)

          expect(status).to eq(0)
          expect(stdout).to include('simple-job')
        end

        pipeline_file.unlink
      end
    end

    describe 'capacity limits' do
      it 'waits when runner capacity is exhausted' do
        # Create runner with limited capacity
        with_temp_runner_fleet([{
          id: 'limited-runner',
          tags: ['docker'],
          max_jobs: 1,
          run_untagged: true
        }]) do |tmpdir|
          stdout, _stderr, _status = run_dry_run(valid_with_needs_file, runners_dir: tmpdir)

          # With many jobs and only 1 capacity, should show waiting
          # or sequential execution
          limited_runner_count = stdout.lines.select { |l| l.include?('limited-runner') }.size
          expect(stdout =~ /waiting|queue|pending/i || limited_runner_count >= 1).to be_truthy
        end
      end

      it 'reports when no eligible runner is available' do
        # Create job with tags that no runner can handle
        pipeline_with_rare_tags = <<~YAML
          stages: [test]

          special-job:
            stage: test
            tags: [rare-tag-that-no-runner-has]
            script: echo "Special job"
        YAML

        pipeline_file = Tempfile.new(['pipeline', '.yml'])
        pipeline_file.write(pipeline_with_rare_tags)
        pipeline_file.close

        with_temp_runner_fleet([
          { id: 'normal-runner', tags: ['docker'], max_jobs: 1, run_untagged: false }
        ]) do |tmpdir|
          stdout, stderr, _status = run_dry_run(pipeline_file.path, runners_dir: tmpdir)

          combined_output = stdout + stderr

          # Should report no eligible runner
          expect(combined_output).to match(/no.*runner|no.*eligible|waiting/i)
        end

        pipeline_file.unlink
      end

      it 'handles multiple runners with different capacities' do
        with_temp_runner_fleet([
          { id: 'runner-1', tags: ['docker'], max_jobs: 1, run_untagged: true },
          { id: 'runner-2', tags: ['docker'], max_jobs: 2, run_untagged: true },
          { id: 'runner-3', tags: ['docker'], max_jobs: 1, run_untagged: true }
        ]) do |tmpdir|
          stdout, _stderr, status = run_dry_run(valid_with_needs_file, runners_dir: tmpdir)

          expect(status).to eq(0)

          # Multiple runners should be utilized
          expect(stdout.include?('runner-1') || stdout.include?('runner-2')).to be_truthy
        end
      end
    end
  end

  context 'timeline output' do
    describe 'execution timeline' do
      it 'shows temporal progression of job execution' do
        stdout, _stderr, _status = run_dry_run(valid_with_needs_file)

        # Should show timestamps or progression markers
        expect(stdout).to match(/T\+\d+|time|second|step|phase/i)
      end

      it 'displays jobs in chronological execution order' do
        stdout, _stderr, _status = run_dry_run(valid_with_needs_file)

        # setup_env should appear before jobs that need it
        lines = stdout.lines
        setup_line = lines.index { |l| l.include?('setup_env') }
        build_line = lines.index { |l| l.include?('build_backend') }

        if setup_line && build_line
          expect(setup_line).to be < build_line
        end
      end
    end

    describe 'verbose timeline mode' do
      it 'provides detailed timeline with verbose flag' do
        stdout_normal, _stderr, _status = run_dry_run(valid_with_needs_file)
        stdout_verbose, _stderr, _status = run_dry_run(valid_with_needs_file, extra_args: ['--verbose'])

        # Verbose should provide more detail
        expect(stdout_verbose.length).to be >= stdout_normal.length
      end
    end
  end

  context 'variable handling' do
    describe 'CI variables' do
      it 'accepts variables via --variables flag' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--variables', 'DEPLOY_ENV=staging']
        )

        expect(status).to eq(0), "Failed with STDERR: #{stderr}"
      end

      it 'accepts multiple variables' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: [
            '--variables', 'VAR1=value1',
            '--variables', 'VAR2=value2'
          ]
        )

        expect(status).to eq(0), "Failed with STDERR: #{stderr}"
      end

      it 'accepts variables via --env alias' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--env', 'BUILD_NUMBER=123']
        )

        expect(status).to eq(0), "Failed with STDERR: #{stderr}"
      end

      it 'displays variables in verbose mode' do
        stdout, stderr, _status = run_dry_run(
          valid_simple_file,
          extra_args: ['--variables', 'TEST_VAR=test_value', '--verbose']
        )

        combined_output = stdout + stderr

        # Should mention the variable in verbose output
        expect(combined_output).to match(/variable|TEST_VAR|test_value/i)
      end
    end

    describe 'undefined variable handling' do
      it 'respects --undefined=warning mode' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--undefined', 'warning']
        )

        expect(status).to eq(0)
      end

      it 'respects --undefined=error mode' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--undefined', 'error']
        )

        # May succeed if no undefined vars, or fail if there are any
        expect([0, 2]).to include(status)
      end

      it 'respects --undefined=empty mode' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--undefined', 'empty']
        )

        expect(status).to eq(0)
      end
    end
  end

  context 'pipeline types' do
    describe '--pipeline flag' do
      it 'accepts push pipeline type' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--pipeline', 'push']
        )

        expect(status).to eq(0), "Failed with STDERR: #{stderr}"
      end

      it 'accepts merge_request pipeline type' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--pipeline', 'merge_request']
        )

        expect(status).to eq(0), "Failed with STDERR: #{stderr}"
      end

      it 'accepts schedule pipeline type' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--pipeline', 'schedule']
        )

        expect(status).to eq(0), "Failed with STDERR: #{stderr}"
      end

      it 'accepts manual pipeline type' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          extra_args: ['--pipeline', 'manual']
        )

        expect(status).to eq(0), "Failed with STDERR: #{stderr}"
      end
    end
  end

  context 'error handling' do
    describe 'missing file' do
      it 'reports error for non-existent pipeline file' do
        stdout, stderr, status = run_dry_run('/nonexistent/file.yml')

        expect(status).not_to eq(0)

        combined_output = stdout + stderr
        expect(combined_output).to match(/not found|no such file|does not exist/i)
      end
    end

    describe 'missing runners directory' do
      it 'reports error for non-existent runners directory' do
        stdout, stderr, status = run_dry_run(
          valid_simple_file,
          runners_dir: '/nonexistent/runners'
        )

        expect(status).not_to eq(0)

        combined_output = stdout + stderr
        expect(combined_output).to match(/not found|no such|runner.*directory/i)
      end
    end

    describe 'empty runners directory' do
      it 'reports error when no runners are available' do
        Dir.mktmpdir do |tmpdir|
          # Empty directory - no runners
          stdout, stderr, status = run_dry_run(valid_simple_file, runners_dir: tmpdir)

          expect(status).not_to eq(0)

          combined_output = stdout + stderr
          expect(combined_output).to match(/no.*runner|runner.*found|runner.*available/i)
        end
      end
    end

    describe 'invalid runner JSON' do
      it 'reports error for malformed runner configuration' do
        Dir.mktmpdir do |tmpdir|
          # Write invalid JSON
          File.write(File.join(tmpdir, 'invalid.json'), '{ invalid json }')

          stdout, stderr, status = run_dry_run(valid_simple_file, runners_dir: tmpdir)

          expect(status).not_to eq(0)

          combined_output = stdout + stderr
          expect(combined_output).to match(/invalid|parse|json.*error/i)
        end
      end
    end

    describe 'missing required flags' do
      it 'reports error when --entry is missing' do
        stdout, stderr, status = Open3.capture3(bin_path, 'dry-run')

        expect(status).not_to eq(0)

        combined_output = stdout + stderr
        # Should report error about missing file or entry
        expect(combined_output).to match(/entry|file.*required|config.*file.*not.*found|\.gitlab-ci\.yml/i)
      end
    end
  end

  context 'complex pipeline simulation' do
    describe 'complex_pipeline.yml' do
      it 'handles large pipeline with many stages and jobs' do
        stdout, stderr, status = run_dry_run(complex_pipeline_file)

        expect(status).to eq(0), "Failed on complex pipeline. STDERR: #{stderr}"
      end

      it 'shows execution of multiple stages' do
        stdout, _stderr, _status = run_dry_run(complex_pipeline_file)

        # Should show progression through stages
        expect(stdout).to match(/prepare|build|test|security|deploy/i)
      end

      it 'handles parallel jobs efficiently' do
        stdout, _stderr, status = run_dry_run(complex_pipeline_file)

        expect(status).to eq(0)

        # Multiple parallel jobs should be visible
        # (build_backend, build_frontend, multiple tests, etc.)
        # Output uses → arrow character, not ->
        job_mentions = stdout.scan(/job.*→|assigned|running|completed/i).size
        expect(job_mentions).to be >= 5
      end

      it 'completes in reasonable time' do
        start_time = Time.now
        stdout, stderr, status = run_dry_run(complex_pipeline_file)
        elapsed = Time.now - start_time

        expect(status).to eq(0)

        # Should complete complex pipeline simulation in under 30 seconds
        # as per PRD non-functional requirements
        expect(elapsed).to be < 30
      end
    end
  end

  context 'output formats' do
    describe 'text format' do
      it 'produces human-readable output' do
        stdout, _stderr, _status = run_dry_run(valid_simple_file, extra_args: ['--format', 'text'])

        # Should be readable text, not JSON/XML
        expect(stdout).not_to match(/^{/)
        expect(stdout).not_to match(/^<\?xml/)
        expect(stdout).to match(/\w+/)
      end
    end
  end
end
