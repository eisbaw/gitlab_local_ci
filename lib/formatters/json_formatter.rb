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

require 'json'
require 'time'
require_relative 'base_formatter'

module Formatters
  # Formats output as JSON
  # Useful for machine-readable output and integration with other tools
  class JsonFormatter < BaseFormatter
    # Format data as JSON
    #
    # @param data [Hash] Data to format
    # @param command [Symbol] The command type
    # @return [String] JSON string
    def format(data, command:)
      # Output the result directly (not wrapped) for test compatibility
      output = make_json_safe(data)

      JSON.pretty_generate(output)
    end

    private

    # Convert data to JSON-safe format
    #
    # @param obj [Object] Object to convert
    # @return [Object] JSON-safe object
    def make_json_safe(obj)
      case obj
      when Symbol
        obj.to_s
      when Time
        obj.utc.iso8601
      when Hash
        obj.each_with_object({}) do |(key, value), result|
          result[make_json_safe(key)] = make_json_safe(value)
        end
      when Array
        obj.map { |item| make_json_safe(item) }
      when String, Numeric, TrueClass, FalseClass, NilClass
        obj
      else
        # For custom objects, try to_h, then to_s as fallback
        if obj.respond_to?(:to_h)
          make_json_safe(obj.to_h)
        else
          obj.to_s
        end
      end
    end
  end
end
