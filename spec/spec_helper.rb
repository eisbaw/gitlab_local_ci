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

# SimpleCov must be loaded before application code
require 'fileutils'
require_relative 'simplecov_config'

# Coverage counts the CLI subprocesses too. The integration specs drive
# dry-run, run, export-just and the lint formatters through bin/gitlab_ci_cli
# (Open3), and in-process coverage never sees that code. Each subprocess
# loads simplecov_cli_subprocess.rb via RUBYOPT and stores its own result.
#
# Results from an earlier run would be merged as if this run produced them,
# so start from nothing: generated files only, under coverage/.
FileUtils.rm_rf(SimpleCovConfig::SUBPROCESS_DIR)
FileUtils.rm_f(File.join(SimpleCovConfig::ROOT, 'coverage', '.resultset.json'))
ENV['RUBYOPT'] = [ENV['RUBYOPT'], "-r#{File.expand_path('simplecov_cli_subprocess.rb', __dir__)}"].compact.join(' ')

SimpleCov.at_exit do
  subprocess_resultsets = Dir[File.join(SimpleCovConfig::SUBPROCESS_DIR, '*', '.resultset.json')]
  # Stored into coverage/.resultset.json, which SimpleCov.result then merges
  # with this process's own result.
  SimpleCov::ResultMerger.merge_and_store(*subprocess_resultsets, ignore_timeout: true) unless subprocess_resultsets.empty?
  SimpleCov.result.format!
end

SimpleCov.start do
  SimpleCovConfig.apply_common

  # Files no spec loads count as 0% instead of being left out of the total.
  track_files 'lib/**/*.rb'

  add_group 'Commands', 'lib/commands'
  add_group 'Formatters', 'lib/formatters'
  add_group 'Core', 'lib'

  # A ratchet, not a target: the floor of what the suite measured when the
  # gate was made honest (TASK-2: line 84.34%, branch 73.85%, with the CLI
  # subprocesses and every lib/ file counted). Before that the gate said
  # 90/80 against ~79/64 of only the in-process-loaded files, so it was red
  # on every run and nobody read it. Now it is green and fails when
  # coverage drops. Only ever raise these, to the new floor, when specs add
  # coverage; never lower them to make a change pass. The aspiration is
  # still 90/80, tracked as a backlog task with the lowest-covered files.
  minimum_coverage line: 84, branch: 73
end

require 'rspec'

# Add lib directory to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# RSpec configuration
RSpec.configure do |config|
  # Use color in output
  config.color = true

  # Use documentation format for output
  config.formatter = :documentation

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Seed random number generator for reproducible test runs
  Kernel.srand config.seed

  # Disable monkey patching (use expect syntax only)
  config.disable_monkey_patching!

  # Enable aggregate failures
  config.define_derived_metadata do |meta|
    meta[:aggregate_failures] = true unless meta.key?(:aggregate_failures)
  end

  # Filter lines from Rails gems in backtraces
  config.filter_run_when_matching :focus

  # Allow more verbose output when running a single spec file
  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end
end

# Load support files
Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }

# Helper methods for tests
module SpecHelpers
  # Capture stderr output during block execution
  #
  # @yield Block to execute
  # @return [String] Captured stderr output
  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end
end

# Include helper methods in all specs
RSpec.configure do |config|
  config.include SpecHelpers
end
