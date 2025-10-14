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

require_relative 'text_formatter'
require_relative 'json_formatter'
require_relative 'junit_formatter'

module Formatters
  # Factory for creating formatter instances
  # Provides a single entry point for obtaining formatters by format string
  class FormatterFactory
    # Supported format types
    FORMATS = {
      'text' => TextFormatter,
      'json' => JsonFormatter,
      'junit' => JunitFormatter
    }.freeze

    # Create a formatter instance for the given format
    #
    # @param format [String] The format type (text, json, junit)
    # @return [BaseFormatter] Formatter instance
    # @raise [ArgumentError] If format is invalid
    def self.create(format)
      format = format.to_s.downcase

      formatter_class = FORMATS[format]
      unless formatter_class
        valid_formats = FORMATS.keys.join(', ')
        raise ArgumentError, "Invalid format: #{format}. Valid formats: #{valid_formats}"
      end

      formatter_class.new
    end

    # Check if a format is supported
    #
    # @param format [String] The format type to check
    # @return [Boolean] True if format is supported
    def self.supported?(format)
      FORMATS.key?(format.to_s.downcase)
    end

    # List all supported formats
    #
    # @return [Array<String>] List of supported format names
    def self.supported_formats
      FORMATS.keys
    end
  end
end
