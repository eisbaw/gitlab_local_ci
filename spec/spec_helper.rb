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
require 'simplecov'

SimpleCov.start do
  # Track coverage in lib directory
  add_filter '/spec/'
  add_filter '/gitlab/'

  # Set minimum coverage threshold to 90%
  minimum_coverage 90

  # Organize coverage by groups
  add_group 'Commands', 'lib/commands'
  add_group 'Formatters', 'lib/formatters'
  add_group 'Core', 'lib'

  # Enable branch coverage (requires SimpleCov 0.18+)
  enable_coverage :branch

  # Report both line and branch coverage
  minimum_coverage line: 90, branch: 80
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
