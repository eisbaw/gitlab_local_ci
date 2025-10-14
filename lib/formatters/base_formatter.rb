# frozen_string_literal: true

module Formatters
  # Abstract base class for output formatters
  # All formatters should inherit from this class and implement the format method
  class BaseFormatter
    # Format the given data for output
    #
    # @param data [Hash] Data to format, structure depends on command:
    #   For lint: { valid: true/false, stages: [], jobs: [], errors: [] }
    #   For dag: { stages: [], jobs: [], dependencies: [] }
    #   For dry-run: { pipeline_id: String, jobs: [], events: [], status: Symbol }
    # @param command [Symbol] The command that generated the data (:lint, :dag, :dry_run)
    # @return [String] Formatted output
    def format(data, command:)
      raise NotImplementedError, "#{self.class.name} must implement #format method"
    end

    protected

    # Validate that data has required keys for the command
    #
    # @param data [Hash] Data to validate
    # @param required_keys [Array<Symbol>] Keys that must be present
    def validate_data(data, required_keys)
      missing_keys = required_keys - data.keys
      unless missing_keys.empty?
        raise ArgumentError, "Missing required keys: #{missing_keys.join(', ')}"
      end
    end
  end
end
