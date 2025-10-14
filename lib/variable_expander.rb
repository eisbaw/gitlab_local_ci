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

# Custom exception raised when an undefined variable is encountered
class UndefinedVariableError < StandardError
  attr_reader :variable_name

  def initialize(variable_name)
    @variable_name = variable_name
    super("Undefined variable: #{variable_name}")
  end
end

# Handles variable expansion in GitLab CI configuration
# Supports ${VAR} and $VAR syntax with configurable undefined variable handling
class VariableExpander
  attr_reader :mode

  VALID_MODES = %i[warning error empty].freeze

  # Initialize the expander with a handling mode for undefined variables
  #
  # @param mode [Symbol] How to handle undefined variables:
  #   - :warning - Log warning and keep original text
  #   - :error - Raise UndefinedVariableError
  #   - :empty - Replace with empty string
  def initialize(mode = :warning)
    unless VALID_MODES.include?(mode)
      raise ArgumentError, "Invalid mode: #{mode}. Must be one of #{VALID_MODES.join(', ')}"
    end

    @mode = mode
  end

  # Expand variables in the given text
  #
  # @param text [String] The text containing variables to expand
  # @param variables [Hash] Variable name => value mapping
  # @return [String] Text with variables expanded
  def expand(text, variables)
    return text if text.nil? || text.empty?

    # Process in two passes:
    # 1. Handle escaped variables ($$VAR -> placeholder, $${VAR} -> placeholder)
    # 2. Expand actual variables and restore escaped ones

    # Step 1: Replace escaped variables with placeholders to protect them
    escaped_map = {}
    placeholder_counter = 0

    # Handle $${VAR} -> ${VAR}
    text = text.gsub(/\$\$\{([A-Za-z_][A-Za-z0-9_]*)\}/) do
      placeholder = "\x00ESCAPED_BRACE_#{placeholder_counter}\x00"
      escaped_map[placeholder] = "${#{Regexp.last_match(1)}}"
      placeholder_counter += 1
      placeholder
    end

    # Handle $$VAR -> $VAR (but not $$$VAR which is $$+$VAR)
    text = text.gsub(/\$\$([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_])/) do
      placeholder = "\x00ESCAPED_SIMPLE_#{placeholder_counter}\x00"
      escaped_map[placeholder] = "$#{Regexp.last_match(1)}"
      placeholder_counter += 1
      placeholder
    end

    # Step 2: Expand ${VAR} syntax
    text = text.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/) do
      var_name = Regexp.last_match(1)
      original = Regexp.last_match(0)
      expand_variable(var_name, original, variables)
    end

    # Step 3: Expand $VAR syntax (word boundary aware)
    text = text.gsub(/\$([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_])/) do
      var_name = Regexp.last_match(1)
      original = Regexp.last_match(0)
      expand_variable(var_name, original, variables)
    end

    # Step 4: Restore escaped variables
    escaped_map.each do |placeholder, original_text|
      text = text.gsub(placeholder, original_text)
    end

    text
  end

  private

  # Expand a single variable reference
  #
  # @param var_name [String] The variable name (without $ or ${})
  # @param original [String] The original text including $ or ${}
  # @param variables [Hash] The variables hash
  # @return [String] The expanded value or handled undefined case
  def expand_variable(var_name, original, variables)
    # Get value from hash
    # Note: Missing keys return nil, explicit nil values also count as undefined
    # This matches GitLab CI behavior: both missing vars and nil vars are undefined
    value = variables[var_name]

    if value.nil?
      handle_undefined(var_name, original)
    else
      # Convert value to string to handle non-string values (integers, booleans, etc.)
      value.to_s
    end
  end

  # Handle an undefined variable according to the configured mode
  #
  # @param variable_name [String] The name of the undefined variable
  # @param original_text [String] The original variable reference (e.g., "${VAR}")
  # @return [String] The replacement text
  def handle_undefined(variable_name, original_text)
    case @mode
    when :warning
      # Emit warning to stderr and keep original text
      warn "Undefined variable: #{variable_name}"
      original_text
    when :error
      # Raise error with variable name
      raise UndefinedVariableError.new(variable_name)
    when :empty
      # Replace with empty string
      ''
    else
      # Should never reach here due to validation in initialize
      raise "Invalid mode: #{@mode}"
    end
  end
end
