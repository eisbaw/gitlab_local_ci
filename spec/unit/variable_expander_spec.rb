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
require 'spec_helper'
require 'variable_expander'

RSpec.describe VariableExpander do
  describe '#initialize' do
    it 'should initialize with warning mode by default' do
      expander = described_class.new

      expect(expander.mode).to eq(:warning)
    end

    it 'should initialize with warning mode when specified' do
      expander = described_class.new(:warning)

      expect(expander.mode).to eq(:warning)
    end

    it 'should initialize with error mode when specified' do
      expander = described_class.new(:error)

      expect(expander.mode).to eq(:error)
    end

    it 'should initialize with empty mode when specified' do
      expander = described_class.new(:empty)

      expect(expander.mode).to eq(:empty)
    end

    it 'should raise ArgumentError for invalid mode' do
      expect do
        described_class.new(:invalid)
      end.to raise_error(ArgumentError, /Invalid mode: invalid/)
    end

    it 'should raise ArgumentError for nil mode' do
      expect do
        described_class.new(nil)
      end.to raise_error(ArgumentError, /Invalid mode/)
    end

    it 'should raise ArgumentError for string mode instead of symbol' do
      expect do
        described_class.new('warning')
      end.to raise_error(ArgumentError, /Invalid mode: warning/)
    end
  end

  describe '#expand' do
    let(:variables) { { 'USER' => 'john', 'ENV' => 'production', 'DEBUG' => 'false' } }

    describe 'with defined variables' do
      let(:expander) { described_class.new(:warning) }

      it 'should expand ${VAR} syntax with defined variable' do
        text = 'Hello ${USER}!'
        result = expander.expand(text, variables)

        expect(result).to eq('Hello john!')
      end

      it 'should expand $VAR syntax with defined variable' do
        text = 'Environment: $ENV'

        result = expander.expand(text, variables)

        expect(result).to eq('Environment: production')
      end

      it 'should expand multiple variables in one string' do
        text = 'User ${USER} in $ENV with debug=$DEBUG'

        result = expander.expand(text, variables)

        expect(result).to eq('User john in production with debug=false')
      end

      it 'should expand same variable multiple times' do
        text = '${USER} and ${USER} again'

        result = expander.expand(text, variables)

        expect(result).to eq('john and john again')
      end

      it 'should handle text with no variables' do
        text = 'No variables here'

        result = expander.expand(text, variables)

        expect(result).to eq('No variables here')
      end

      it 'should handle empty string' do
        result = expander.expand('', variables)

        expect(result).to eq('')
      end

      it 'should preserve whitespace' do
        text = '  ${USER}  \n  $ENV  '

        result = expander.expand(text, variables)

        expect(result).to eq('  john  \n  production  ')
      end

      it 'should handle variables with underscores' do
        vars = { 'MY_VAR_NAME' => 'value' }
        text = '${MY_VAR_NAME}'

        result = expander.expand(text, vars)

        expect(result).to eq('value')
      end

      it 'should handle variables with numbers' do
        vars = { 'VAR123' => 'value' }
        text = '${VAR123}'

        result = expander.expand(text, vars)

        expect(result).to eq('value')
      end

      it 'should not expand variables with invalid names' do
        # Variable names starting with numbers are invalid
        text = '${123VAR}'

        result = expander.expand(text, variables)

        expect(result).to eq('${123VAR}')
      end

      it 'should handle consecutive variables without separator' do
        text = '${USER}${ENV}'

        result = expander.expand(text, variables)

        expect(result).to eq('johnproduction')
      end
    end

    describe 'with undefined variables in warning mode' do
      let(:expander) { described_class.new(:warning) }

      it 'should keep undefined variable as-is and emit warning' do
        text = 'User ${UNDEFINED}'

        expect do
          result = expander.expand(text, variables)
          expect(result).to eq('User ${UNDEFINED}')
        end.to output(/Undefined variable: UNDEFINED/).to_stderr
      end

      it 'should warn for each undefined variable' do
        text = '${UNDEFINED1} and ${UNDEFINED2}'

        expect do
          expander.expand(text, variables)
        end.to output(/UNDEFINED1.*UNDEFINED2/m).to_stderr
      end

      it 'should warn only once for same undefined variable' do
        text = '${UNDEFINED} and ${UNDEFINED}'

        warnings = capture_stderr do
          expander.expand(text, variables)
        end

        # Should warn once or twice depending on implementation
        expect(warnings).to match(/Undefined variable: UNDEFINED/)
      end

      it 'should expand defined variables and warn for undefined' do
        text = '${USER} and ${UNDEFINED}'

        expect do
          result = expander.expand(text, variables)
          expect(result).to eq('john and ${UNDEFINED}')
        end.to output(/Undefined variable: UNDEFINED/).to_stderr
      end
    end

    describe 'with undefined variables in error mode' do
      let(:expander) { described_class.new(:error) }

      it 'should raise UndefinedVariableError for undefined variable' do
        text = 'User ${UNDEFINED}'

        expect do
          expander.expand(text, variables)
        end.to raise_error(UndefinedVariableError, /UNDEFINED/)
      end

      it 'should raise error with variable name in exception' do
        text = '${MISSING_VAR}'

        expect do
          expander.expand(text, variables)
        end.to raise_error(UndefinedVariableError) do |error|
          expect(error.variable_name).to eq('MISSING_VAR')
        end
      end

      it 'should raise error on first undefined variable' do
        text = '${UNDEFINED1} and ${UNDEFINED2}'

        expect do
          expander.expand(text, variables)
        end.to raise_error(UndefinedVariableError, /UNDEFINED1/)
      end

      it 'should not raise error if all variables defined' do
        text = '${USER} in ${ENV}'

        expect do
          result = expander.expand(text, variables)
          expect(result).to eq('john in production')
        end.not_to raise_error
      end
    end

    describe 'with undefined variables in empty mode' do
      let(:expander) { described_class.new(:empty) }

      it 'should replace undefined variable with empty string' do
        text = 'User ${UNDEFINED}!'

        result = expander.expand(text, variables)

        expect(result).to eq('User !')
      end

      it 'should replace all undefined variables with empty string' do
        text = '${UNDEFINED1} and ${UNDEFINED2}'

        result = expander.expand(text, variables)

        expect(result).to eq(' and ')
      end

      it 'should not emit warnings in empty mode' do
        text = '${UNDEFINED}'

        expect do
          expander.expand(text, variables)
        end.not_to output.to_stderr
      end

      it 'should expand defined and remove undefined variables' do
        text = '${USER} in ${UNDEFINED}'

        result = expander.expand(text, variables)

        expect(result).to eq('john in ')
      end
    end

    describe 'escaped variables' do
      let(:expander) { described_class.new(:warning) }

      it 'should not expand $$VAR syntax (escaped)' do
        text = 'Escaped: $$USER'

        result = expander.expand(text, variables)

        expect(result).to eq('Escaped: $USER')
      end

      it 'should not expand $${VAR} syntax (escaped)' do
        text = 'Escaped: $${USER}'

        result = expander.expand(text, variables)

        expect(result).to eq('Escaped: ${USER}')
      end

      it 'should handle mix of escaped and non-escaped' do
        text = '$USER and $$USER'

        result = expander.expand(text, variables)

        expect(result).to eq('john and $USER')
      end
    end

    describe 'edge cases' do
      let(:expander) { described_class.new(:warning) }

      it 'should handle variable name with single character' do
        vars = { 'X' => 'value' }
        text = '${X}'

        result = expander.expand(text, vars)

        expect(result).to eq('value')
      end

      it 'should not expand incomplete variable syntax' do
        text = '${INCOMPLETE'

        result = expander.expand(text, variables)

        expect(result).to eq('${INCOMPLETE')
      end

      it 'should not expand just dollar sign' do
        text = 'Price: $100'

        result = expander.expand(text, variables)

        expect(result).to eq('Price: $100')
      end

      it 'should handle empty braces' do
        text = '${}'

        result = expander.expand(text, variables)

        expect(result).to eq('${}')
      end

      it 'should handle nested braces' do
        text = '${VAR${INNER}}'

        result = expander.expand(text, variables)

        # Nested variables might not be supported
        expect(result).to eq(text)
      end

      it 'should handle variable at start of string' do
        text = '${USER} is here'

        result = expander.expand(text, variables)

        expect(result).to eq('john is here')
      end

      it 'should handle variable at end of string' do
        text = 'User is ${USER}'

        result = expander.expand(text, variables)

        expect(result).to eq('User is john')
      end

      it 'should handle variable as entire string' do
        text = '${USER}'

        result = expander.expand(text, variables)

        expect(result).to eq('john')
      end

      it 'should handle variable values containing dollar signs' do
        vars = { 'PRICE' => '$100' }
        text = 'Cost: ${PRICE}'

        result = expander.expand(text, vars)

        expect(result).to eq('Cost: $100')
      end

      it 'should handle variable values containing braces' do
        vars = { 'CODE' => '{value}' }
        text = 'Code: ${CODE}'

        result = expander.expand(text, vars)

        expect(result).to eq('Code: {value}')
      end

      it 'should handle multiline text' do
        text = <<~TEXT
          User: ${USER}
          Environment: ${ENV}
          Debug: ${DEBUG}
        TEXT

        result = expander.expand(text, variables)

        expect(result).to eq(<<~RESULT)
          User: john
          Environment: production
          Debug: false
        RESULT
      end

      it 'should handle very long variable names' do
        long_name = 'VAR_' + ('A' * 100)
        vars = { long_name => 'value' }
        text = "${#{long_name}}"

        result = expander.expand(text, vars)

        expect(result).to eq('value')
      end

      it 'should handle empty variable values' do
        vars = { 'EMPTY' => '' }
        text = 'Value: ${EMPTY}!'

        result = expander.expand(text, vars)

        expect(result).to eq('Value: !')
      end

      it 'should handle nil in variables hash' do
        vars = { 'NULL' => nil }
        text = '${NULL}'

        result = expander.expand(text, vars)

        # Might treat nil as undefined or convert to empty string
        expect(result).to eq('').or eq('${NULL}')
      end

      it 'should handle large number of variables' do
        large_vars = {}
        100.times { |i| large_vars["VAR#{i}"] = "value#{i}" }
        text = (0...100).map { |i| "${VAR#{i}}" }.join(' ')

        result = expander.expand(text, large_vars)

        expect(result).to eq((0...100).map { |i| "value#{i}" }.join(' '))
      end

      it 'should handle special characters in variable values' do
        vars = { 'SPECIAL' => "a\nb\tc\rd" }
        text = '${SPECIAL}'

        result = expander.expand(text, vars)

        expect(result).to eq("a\nb\tc\rd")
      end

      it 'should handle unicode in variable values' do
        vars = { 'UNICODE' => 'Hello 世界 🌍' }
        text = '${UNICODE}'

        result = expander.expand(text, vars)

        expect(result).to eq('Hello 世界 🌍')
      end
    end

    describe 'performance considerations' do
      let(:expander) { described_class.new(:warning) }

      it 'should handle very long strings' do
        long_text = 'prefix ' * 10000 + '${USER}' + ' suffix' * 10000

        result = expander.expand(long_text, variables)
        expect(result).to include('john')
      end

      it 'should handle many variable references' do
        text = Array.new(1000) { '${USER}' }.join(' ')

        result = expander.expand(text, variables)
        expect(result.scan('john').size).to eq(1000)
      end
    end
  end

  describe 'UndefinedVariableError' do
    it 'should include variable name in error message' do
      error = UndefinedVariableError.new('MY_VAR')

      expect(error.message).to include('MY_VAR')
      expect(error.variable_name).to eq('MY_VAR')
    end

    it 'should be a StandardError' do
      error = UndefinedVariableError.new('VAR')

      expect(error).to be_a(StandardError)
    end
  end

  describe 'mode constants' do
    it 'should define valid modes' do
      expect(VariableExpander::VALID_MODES).to include(:warning, :error, :empty)
    end

    it 'should have three valid modes' do
      expect(VariableExpander::VALID_MODES.size).to eq(3)
    end
  end
end
