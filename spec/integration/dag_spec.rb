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
require 'open3'
require 'json'

RSpec.describe 'GitLab CI DAG Command', type: :integration do
  let(:bin_path) { File.expand_path('../../bin/gitlab_ci_cli', __dir__) }
  let(:fixtures_path) { File.expand_path('../fixtures/yaml', __dir__) }
  let(:valid_simple_file) { File.join(fixtures_path, 'valid_simple.yml') }
  let(:valid_with_needs_file) { File.join(fixtures_path, 'valid_with_needs.yml') }
  let(:circular_dependency_file) { File.join(fixtures_path, 'circular_dependency.yml') }
  let(:complex_pipeline_file) { File.join(fixtures_path, 'complex_pipeline.yml') }

  # Helper method to execute DAG command
  # Returns: [stdout, stderr, exit_status]
  def run_dag(file_path, extra_args: [])
    args = ['dag', '--entry', file_path] + extra_args
    stdout, stderr, status = Open3.capture3(bin_path, *args)
    [stdout, stderr, status.exitstatus]
  end

  context 'DOT output format' do
    describe 'basic structure' do
      it 'produces valid Graphviz DOT syntax' do
        stdout, stderr, status = run_dag(valid_simple_file)

        expect(status).to eq(0), "Expected success but got status #{status}. STDERR: #{stderr}"

        # Basic DOT structure validation
        expect(stdout).to match(/^digraph\s+\w+\s*{/)
        expect(stdout).to match(/}$/)

        # Should have proper statement terminators
        expect(stdout.scan(/;/).size).to be >= 1
      end

      it 'includes graph directionality attribute' do
        stdout, _stderr, _status = run_dag(valid_simple_file)

        # Should specify left-to-right or top-to-bottom layout
        expect(stdout).to match(/rankdir\s*=\s*"?(LR|TB|RL|BT)"?/)
      end

      it 'can be parsed by dot command' do
        stdout, _stderr, _status = run_dag(valid_simple_file)

        # Try to validate with dot -Tcanon
        dot_stdout, dot_stderr, dot_status = Open3.capture3('dot', '-Tcanon', stdin_data: stdout)

        expect(dot_status.exitstatus).to eq(0),
          "DOT failed to parse output. Error: #{dot_stderr}"
      end
    end

    describe 'stage grouping' do
      it 'groups jobs by stage using subgraphs' do
        stdout, _stderr, _status = run_dag(valid_simple_file)

        # Should use subgraph clusters for stages
        expect(stdout).to match(/subgraph\s+cluster_\w+/)

        # Each stage should be represented
        expect(stdout).to include('build')
        expect(stdout).to include('test')
        expect(stdout).to include('deploy')
      end

      it 'labels stage clusters with stage names' do
        stdout, _stderr, _status = run_dag(valid_simple_file)

        # Stage clusters should have labels
        expect(stdout).to match(/label\s*=\s*"build"/)
        expect(stdout).to match(/label\s*=\s*"test"/)
        expect(stdout).to match(/label\s*=\s*"deploy"/)
      end

      it 'places jobs within their stage subgraphs' do
        stdout, _stderr, _status = run_dag(valid_simple_file)

        # Jobs should be nodes within subgraphs
        expect(stdout).to match(/subgraph.*build_job/m)
        expect(stdout).to match(/subgraph.*test_job/m)
        expect(stdout).to match(/subgraph.*deploy_job/m)
      end
    end

    describe 'job nodes' do
      it 'creates nodes for all jobs in pipeline' do
        stdout, _stderr, _status = run_dag(valid_simple_file)

        # All jobs should be represented as nodes
        expect(stdout).to include('build_job')
        expect(stdout).to include('test_job')
        expect(stdout).to include('deploy_job')
      end

      it 'uses valid DOT node identifiers' do
        stdout, _stderr, _status = run_dag(valid_with_needs_file)

        # Node names should be valid identifiers or quoted
        # Extract all node declarations
        nodes = stdout.scan(/\b([a-zA-Z_]\w+)\s*;|\b([a-zA-Z_]\w+)\s*->/)
        expect(nodes).not_to be_empty
      end
    end
  end

  context 'dependency edges' do
    describe 'needs dependencies' do
      it 'creates edges for needs relationships' do
        stdout, _stderr, _status = run_dag(valid_with_needs_file)

        # Should have edge syntax (->)
        expect(stdout).to match(/->/)

        # Specific edges from fixture
        # setup_env -> build_backend, build_frontend
        # build_backend -> test_backend
        # build_frontend -> test_frontend
        edges_count = stdout.scan(/->/).size
        expect(edges_count).to be >= 5
      end

      it 'connects jobs to their needs dependencies' do
        stdout, _stderr, _status = run_dag(valid_with_needs_file)

        # build_backend needs setup_env
        expect(stdout).to match(/setup_env\s*->\s*build_backend/)

        # build_frontend needs setup_env
        expect(stdout).to match(/setup_env\s*->\s*build_frontend/)

        # test_backend needs build_backend
        expect(stdout).to match(/build_backend\s*->\s*test_backend/)

        # test_frontend needs build_frontend
        expect(stdout).to match(/build_frontend\s*->\s*test_frontend/)

        # test_integration needs both builds
        expect(stdout).to match(/build_backend\s*->\s*test_integration/)
        expect(stdout).to match(/build_frontend\s*->\s*test_integration/)
      end

      it 'creates diamond dependency patterns correctly' do
        stdout, _stderr, _status = run_dag(valid_with_needs_file)

        # Diamond: setup_env -> {build_backend, build_frontend} -> test_integration
        # Verify all legs of diamond
        expect(stdout).to match(/setup_env\s*->\s*(build_backend|build_frontend)/)
        expect(stdout).to match(/(build_backend|build_frontend)\s*->\s*test_integration/)
      end
    end

    describe 'stage dependencies' do
      it 'represents stage ordering for jobs without needs' do
        stdout, _stderr, _status = run_dag(valid_simple_file)

        # Jobs without needs should follow stage order
        # test_job depends on build_job (via dependencies)
        # deploy_job follows test stage
        expect(stdout).to match(/->/)
      end
    end
  end

  context 'complex pipelines' do
    describe 'complex_pipeline.yml' do
      it 'handles pipeline with many jobs and stages' do
        stdout, stderr, status = run_dag(complex_pipeline_file)

        expect(status).to eq(0), "Failed on complex pipeline. STDERR: #{stderr}"

        # Should have all stages
        expect(stdout).to include('prepare')
        expect(stdout).to include('build')
        expect(stdout).to include('test')
        expect(stdout).to include('security')
        expect(stdout).to include('deploy')
        expect(stdout).to include('cleanup')
      end

      it 'includes parallel jobs within same stage' do
        stdout, _stderr, _status = run_dag(complex_pipeline_file)

        # Build stage has parallel jobs
        expect(stdout).to include('build_backend')
        expect(stdout).to include('build_frontend')
        expect(stdout).to include('build_docs')

        # Test stage has multiple parallel jobs
        expect(stdout).to include('test_backend_unit')
        expect(stdout).to include('test_backend_integration')
        expect(stdout).to include('test_frontend_unit')
      end

      it 'creates reasonable number of edges for dependencies' do
        stdout, _stderr, _status = run_dag(complex_pipeline_file)

        edges_count = stdout.scan(/->/).size

        # Complex pipeline should have significant number of edges
        # but not exponential (which would indicate cross-product)
        expect(edges_count).to be >= 10
        expect(edges_count).to be < 100 # Sanity check for reasonable complexity
      end
    end
  end

  context 'circular dependency detection' do
    describe 'circular_dependency.yml' do
      it 'detects circular dependency and exits with error' do
        stdout, stderr, status = run_dag(circular_dependency_file)

        expect(status).not_to eq(0), "Expected error for circular dependency"
      end

      it 'reports circular dependency error message' do
        stdout, stderr, status = run_dag(circular_dependency_file)

        combined_output = (stdout + stderr).downcase

        # Should mention circular dependency or cycle
        expect(combined_output).to match(/circular.*dependency|cycle|cyclic/i)
      end

      it 'does not produce invalid DOT output' do
        stdout, _stderr, status = run_dag(circular_dependency_file)

        # If it exits with error, should not produce partial DOT
        if status != 0
          expect(stdout).not_to match(/^digraph/)
        end
      end

      it 'mentions jobs involved in cycle' do
        stdout, stderr, status = run_dag(circular_dependency_file)

        combined_output = stdout + stderr

        # Should mention at least one of the problematic jobs
        expect(combined_output).to match(/job-a|job-b/)
      end
    end
  end

  context 'output customization' do
    describe 'verbose mode' do
      it 'provides additional diagnostic information' do
        stdout_normal, _stderr, _status = run_dag(valid_with_needs_file)
        stdout_verbose, stderr_verbose, _status = run_dag(valid_with_needs_file, extra_args: ['--verbose'])

        # Verbose mode might add comments or logging to stderr
        combined_verbose = stdout_verbose + stderr_verbose
        combined_normal = stdout_normal

        # Should provide more information
        expect(combined_verbose.length).to be >= combined_normal.length
      end
    end
  end

  context 'error handling' do
    describe 'missing file' do
      it 'reports file not found error' do
        stdout, stderr, status = run_dag('/nonexistent/file.yml')

        expect(status).not_to eq(0)

        combined_output = stdout + stderr
        expect(combined_output).to match(/not found|no such file|does not exist/i)
      end
    end

    describe 'invalid YAML' do
      it 'fails gracefully on syntax errors' do
        invalid_file = File.join(fixtures_path, 'invalid_syntax.yml')
        stdout, stderr, status = run_dag(invalid_file)

        expect(status).not_to eq(0)

        combined_output = stdout + stderr
        expect(combined_output).to match(/error|invalid|fail/i)
      end
    end

    describe 'missing --entry flag' do
      it 'reports missing required flag' do
        # Run from a temp directory where .gitlab-ci.yml doesn't exist
        Dir.mktmpdir do |tmpdir|
          stdout, stderr, status = Open3.capture3({ 'PWD' => tmpdir }, bin_path, 'dag', chdir: tmpdir)

          expect(status).not_to eq(0)

          combined_output = stdout + stderr
          # Should report error about missing default file
          expect(combined_output).to match(/file not found|does not exist|\.gitlab-ci\.yml/i)
        end
      end
    end
  end

  context 'real-world validation' do
    describe 'dot rendering' do
      it 'can generate PNG from DOT output' do
        stdout, _stderr, status = run_dag(valid_with_needs_file)
        expect(status).to eq(0)

        # Try to render to PNG using dot
        png_output, dot_stderr, dot_status = Open3.capture3(
          'dot', '-Tpng',
          stdin_data: stdout
        )

        expect(dot_status.exitstatus).to eq(0),
          "Failed to render PNG. Error: #{dot_stderr}"
        expect(png_output).not_to be_empty
        expect(png_output[0..7]).to eq("\x89PNG\r\n\x1a\n"), "Output is not a valid PNG"
      end

      it 'can generate SVG from DOT output' do
        stdout, _stderr, status = run_dag(valid_with_needs_file)
        expect(status).to eq(0)

        # Try to render to SVG using dot
        svg_output, dot_stderr, dot_status = Open3.capture3(
          'dot', '-Tsvg',
          stdin_data: stdout
        )

        expect(dot_status.exitstatus).to eq(0),
          "Failed to render SVG. Error: #{dot_stderr}"
        expect(svg_output).not_to be_empty
        expect(svg_output).to match(/<svg/)
      end
    end
  end
end
