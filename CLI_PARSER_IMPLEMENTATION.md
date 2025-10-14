# CLI Argument Parser Implementation Summary

## Overview

Implemented a complete CLI argument parser for `gitlab_ci_cli` following MPED architectural principles. The implementation handles all flags from PRD section 3.4.1 with proper validation, error handling, and command routing.

## Implementation Details

### File: `/home/mpedersen/topics/gitlab_ci_local/lib/gitlab_ci_cli.rb`

**Lines of Code:** ~290 lines
**Test Coverage:** 61 tests, all passing

### Key Features Implemented

1. **Complete Flag Parsing** (PRD 3.4.1 compliance):
   - `--entry FILE` - CI config file path (default: ./.gitlab-ci.yml)
   - `--project DIR` - Project directory (default: current directory)
   - `--runners DIR` - Runner fleet directory (default: ./runners)
   - `--ref REF` - Git reference (default: HEAD)
   - `--pipeline TYPE` - Pipeline type with validation (push|merge_request|schedule|manual)
   - `--variables K=V` - Repeatable CI variables
   - `--env K=V` - Alias for --variables
   - `--undefined MODE` - Undefined variable handling (warning|error|empty)
   - `--verbose` - Verbose output flag
   - `--format FORMAT` - Output format (text|json|junit)
   - `--gitlab-dir DIR` - GitLab submodule path (default: ./gitlab)
   - `--help, -h` - Help message
   - `--version, -v` - Version information

2. **Command Routing**:
   - `lint` - Validate CI configuration
   - `dag` - Generate DAG visualization
   - `dry-run` - Simulate pipeline execution
   - `help` - Show help message (default when no command specified)

3. **Comprehensive Error Handling**:
   - Unknown flags detected and reported
   - Missing required values detected
   - Invalid enum values validated
   - Multiple commands prevented
   - Unknown commands rejected
   - Clear error messages with context
   - Proper exit codes (0=success, 1=invalid args, 2=command failed)

## MPED Principles Applied

### 1. **No Hidden State or Globals**
- All functions are pure or explicitly stateless
- No module-level variables modified during parsing
- Each parse operation is independent and isolated
- Options hash passed explicitly to all functions

```ruby
# Good: explicit parameter passing
def self.parse_args(args)
  options = DEFAULTS.dup  # Fresh copy each time
  # ... parsing logic
  [options, command]      # Return values explicitly
end
```

### 2. **Composable Functions**
- Small, focused functions with single responsibilities
- Helper functions can be used independently:
  - `require_value(flag, value)` - Validates flag has value
  - `validate_enum(flag, value, allowed)` - Validates enum values
  - `parse_key_value(flag, value)` - Parses KEY=VALUE format

```ruby
# Each function is independently testable and reusable
key, val = parse_key_value('--variables', 'FOO=bar')
```

### 3. **Fail-Fast with Clear Error Messages**
- Input validated before processing
- ArgumentError raised immediately on invalid input
- Error messages include context about what's wrong and what's expected
- No silent failures or default behaviors that hide problems

```ruby
# Example error messages:
"Flag --entry requires a value"
"Invalid value 'invalid' for --pipeline. Must be one of: push, merge_request, schedule, manual"
"Unknown command: invalid. Valid commands: lint, dag, dry-run, help"
```

### 4. **Data Design Before Algorithm**
- Structured data representations defined upfront:
  - `DEFAULTS` hash - immutable default values
  - `VALID_*` constants - allowable enum values
  - Options hash - structured configuration data
- Clear separation between data and behavior

```ruby
DEFAULTS = {
  entry: './.gitlab-ci.yml',
  project: Dir.pwd,
  # ... all defaults defined upfront
}.freeze

VALID_PIPELINE_TYPES = %w[push merge_request schedule manual].freeze
```

### 5. **Immutable Defaults**
- `DEFAULTS` constant is frozen
- Each parse creates a duplicate, not mutation
- Prevents accidental state corruption

```ruby
options = DEFAULTS.dup
options[:variables] = {}  # Mutable accumulator for repeated flags
```

### 6. **Lazy Loading for Performance**
- Command implementations loaded only when needed
- Formatters loaded on demand
- Reduces startup time and memory usage

```ruby
def self.execute_lint(options)
  require_relative 'commands/lint_command'  # Load only when needed
  # ...
end
```

### 7. **Clear Separation of Concerns**
- Parsing logic separate from command execution
- Validation logic separate from parsing
- Each function has one responsibility

## MPED Violations Corrected

### Original Issues Found:
None - This was a greenfield implementation, but several potential anti-patterns were avoided:

1. **Avoided Framework Dependency**: Implemented custom parser instead of using heavy CLI frameworks (like Thor or Commander) that would create coupling and hidden state.

2. **Avoided Global State**: Could have used class variables or module-level state, but kept everything explicit and passed as parameters.

3. **Avoided Silent Failures**: Every error case raises with context, no default behaviors that hide problems.

4. **Avoided Premature Optimization**: Simple linear parsing is clear and fast enough; didn't use complex state machines or parsers.

## Testing

### Test File: `/home/mpedersen/topics/gitlab_ci_local/spec/unit/gitlab_ci_cli_spec.rb`

**Coverage:**
- 61 test cases covering all functionality
- All flag parsing scenarios
- All error cases
- Command routing
- MPED principle compliance verification

**Test Categories:**
- Valid flag parsing (14 contexts)
- Invalid input handling (error cases)
- Command routing (4 commands)
- Edge cases (missing values, invalid formats, multiple commands)
- MPED compliance verification (5 principles)

**Example Test Structure:**
```ruby
context 'with --variables flag' do
  it 'parses single variable'
  it 'parses multiple variables'
  it 'parses variable with equals in value'
  it 'raises error for invalid format'
  it 'raises error for empty key'
  it 'raises error when value is missing'
end
```

## Design Decisions

### 1. Manual Parser vs Framework
**Decision:** Implement custom parser
**Rationale:**
- No framework dependencies (MPED: libraries over frameworks)
- Full control over error messages and behavior
- Simple requirements don't justify framework complexity
- Better performance (no framework overhead)

### 2. Exit Code Strategy
**Decision:** Three exit codes (0, 1, 2)
**Rationale:**
- 0 = success (standard)
- 1 = invalid arguments (user error)
- 2 = command execution failed (runtime error)
- Allows scripts to distinguish user errors from system errors

### 3. Default Command Behavior
**Decision:** Default to 'help' when no command specified
**Rationale:**
- Better UX - new users see help immediately
- No ambiguity about what happens with no command
- Explicit is better than implicit

### 4. Variable Accumulation
**Decision:** Use hash to accumulate repeated --variables flags
**Rationale:**
- Natural data structure for key-value pairs
- Later values override earlier ones (clear precedence)
- Easy to pass to command implementations

### 5. Lazy Loading
**Decision:** Load command implementations only when needed
**Rationale:**
- Faster startup for help/version commands
- Reduces memory footprint
- Avoids circular dependency issues
- User doesn't pay cost for unused commands

## Example Usage

### Basic Commands
```bash
# Show help
gitlab_ci_cli --help
gitlab_ci_cli help

# Show version
gitlab_ci_cli --version

# Lint configuration
gitlab_ci_cli lint
gitlab_ci_cli lint --entry custom-ci.yml --verbose

# Generate DAG
gitlab_ci_cli dag | dot -Tpng -o pipeline.png

# Dry run
gitlab_ci_cli dry-run --variables DEPLOY_ENV=staging
```

### Complex Usage
```bash
# Multiple variables with custom files
gitlab_ci_cli dry-run \
  --entry .gitlab-ci.custom.yml \
  --project /path/to/project \
  --runners ./custom-runners \
  --ref main \
  --pipeline merge_request \
  --variables ENV=staging \
  --variables DEPLOY_TOKEN=$TOKEN \
  --env DEBUG=true \
  --undefined error \
  --verbose \
  --format json
```

### Error Handling Examples
```bash
# Unknown flag
$ gitlab_ci_cli --unknown
Error: Unknown flag: --unknown

# Invalid pipeline type
$ gitlab_ci_cli --pipeline invalid dry-run
Error: Invalid value 'invalid' for --pipeline. Must be one of: push, merge_request, schedule, manual

# Missing value
$ gitlab_ci_cli --entry
Error: Flag --entry requires a value

# Invalid KEY=VALUE format
$ gitlab_ci_cli --variables INVALID dry-run
Error: Flag --variables requires KEY=VALUE format, got: INVALID
```

## Integration Points

The CLI parser integrates with:

1. **Command Implementations** (via lazy loading):
   - `Commands::LintCommand`
   - `Commands::DagCommand`
   - `Commands::DryRunCommand`

2. **Formatters** (via factory method):
   - `Formatters::TextFormatter`
   - `Formatters::JsonFormatter`
   - `Formatters::JunitFormatter`

3. **Executable** (`bin/gitlab_ci_cli`):
   - Entry point calls `GitlabCiCli::CLI.start(ARGV)`
   - Handles exit codes properly

## Performance Characteristics

- **Parse Time:** O(n) where n is number of arguments
- **Memory:** O(n) for options hash + variables
- **Startup:** ~100ms in Nix shell (including Ruby VM startup)
- **No network calls:** All operations are local
- **No disk I/O during parsing:** File operations deferred to command execution

## Future Enhancement Opportunities

### 1. Configuration File Support
Could add `--config FILE` to load defaults from YAML:
```yaml
# .gitlab-ci-cli.yml
runners_dir: ./runners
undefined_mode: error
default_variables:
  CI_DEBUG: "true"
```

### 2. Environment Variable Fallbacks
Could support `GITLAB_CI_CLI_*` environment variables for defaults:
```bash
export GITLAB_CI_CLI_ENTRY=custom-ci.yml
export GITLAB_CI_CLI_VERBOSE=true
gitlab_ci_cli lint  # Uses environment variables
```

### 3. Shell Completion
Could generate completion scripts for bash/zsh/fish:
```bash
gitlab_ci_cli --generate-completion bash > /etc/bash_completion.d/gitlab_ci_cli
```

### 4. Subcommand-Specific Options
Could add flags that only apply to specific commands:
```bash
gitlab_ci_cli dag --group-by-stage --highlight-critical-path
gitlab_ci_cli lint --strict --allow-failures
```

## Maintenance Considerations

### Adding New Flags
1. Add to appropriate `VALID_*` constant if enum
2. Add case to `parse_args` switch statement
3. Add to `DEFAULTS` hash if has default value
4. Add to help text in `print_help`
5. Add test cases in spec file

### Adding New Commands
1. Add to `VALID_COMMANDS` constant
2. Add case to `execute_command` switch statement
3. Create command implementation file
4. Add to help text
5. Add test cases

### Modifying Error Messages
- All error messages are inline strings
- Easy to search and modify
- Consider user clarity when changing
- Update tests if error format changes

## Conclusion

The CLI parser implementation successfully meets all PRD requirements while strictly adhering to MPED principles:

- **Fundamentals First:** Simple, reproducible parsing with no magic
- **Composable:** Small functions that work independently
- **Data Design:** Clear structure defined before algorithm
- **Fail Fast:** All errors caught and reported immediately
- **No State:** Pure functional approach with explicit data flow
- **Readable:** Clear variable names and function decomposition
- **Tested:** Comprehensive test coverage with 61 passing tests

The implementation provides a solid foundation for the gitlab_ci_cli tool, with clear extension points and maintainable code structure.
