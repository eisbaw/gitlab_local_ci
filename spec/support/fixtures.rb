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
