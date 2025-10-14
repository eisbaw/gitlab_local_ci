# frozen_string_literal: true

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
