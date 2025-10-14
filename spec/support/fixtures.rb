# frozen_string_literal: true

require 'yaml'
require 'json'

module FixtureHelpers
  # Get the path to the fixtures directory
  def fixtures_path
    File.expand_path('../fixtures', __dir__)
  end

  # Load a YAML fixture file
  #
  # @param filename [String] the name of the fixture file (relative to spec/fixtures/yaml)
  # @return [Hash] the parsed YAML content
  def load_yaml_fixture(filename)
    path = File.join(fixtures_path, 'yaml', filename)
    YAML.load_file(path)
  end

  # Load a JSON fixture file
  #
  # @param filename [String] the name of the fixture file (relative to spec/fixtures/runners)
  # @return [Hash] the parsed JSON content
  def load_runner_fixture(filename)
    path = File.join(fixtures_path, 'runners', filename)
    JSON.parse(File.read(path))
  end

  # Get the full path to a fixture file
  #
  # @param type [String] the fixture type directory (e.g., 'yaml', 'runners')
  # @param filename [String] the name of the fixture file
  # @return [String] the full path to the fixture file
  def fixture_path(type, filename)
    File.join(fixtures_path, type, filename)
  end

  # TODO: Add helper for loading multiple fixtures
  # TODO: Add helper for creating temporary fixture files
  # TODO: Add helper for modifying fixtures on the fly
  # TODO: Add helper for validating fixture structure
end

# Include fixture helpers in all specs
RSpec.configure do |config|
  config.include FixtureHelpers
end
