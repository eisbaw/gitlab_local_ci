# frozen_string_literal: true

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
