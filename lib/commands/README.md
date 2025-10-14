# Commands

This directory contains command implementations for the GitLab CI CLI.

## Design Principles

All commands follow MPED architectural principles:

### 1. Pure Functions
Commands are implemented as pure functions:
- **Input**: Options hash containing all parameters
- **Output**: Result object with structured data
- **No Side Effects**: No global state, no hidden dependencies

### 2. Composability
Commands return structured data that formatters can transform:
```ruby
result = LintCommand.execute(options)  # Returns Result object
formatter = TextFormatter.new
output = formatter.format(result.to_h, command: :lint)
```

### 3. Fail Fast with Context
Commands validate inputs early and provide detailed error messages:
- File not found? Tell user exactly which file and where
- Missing dependency? Provide exact command to fix it
- Invalid configuration? Show specific validation errors

### 4. Single Source of Truth
- GitLab's YamlProcessor is the authority on validation
- We don't reimplement validation logic
- We delegate to upstream code and handle integration

## LintCommand

The `LintCommand` validates GitLab CI YAML files using GitLab's own YamlProcessor.

### Dependencies

**Important**: GitLab's YamlProcessor has ~100+ gem dependencies. Users must install these separately:

```bash
cd gitlab && bundle install
```

Or add to your Gemfile:
```ruby
eval_gemfile 'gitlab/Gemfile'
```

### Design Decisions

1. **Result Object Pattern**: Returns a `Result` object instead of directly outputting
   - Makes testing easier
   - Allows different formatters
   - Separates business logic from presentation

2. **Explicit Gem Loading**: We document required dependencies rather than trying to hide them
   - Fails fast with helpful messages if gems missing
   - User has control over dependency installation
   - No magical Bundler switching

3. **GitLab Gems Path**: GitLab moved utilities to `gems/` directory
   - We add these to load path explicitly
   - This allows GitLab to evolve its internal structure

### Error Handling

The command handles these error cases:

1. **File Not Found**: Clear message with file path
2. **YAML Syntax Error**: Caught early with Psych error details
3. **GitLab Validation Error**: Forwarded from YamlProcessor
4. **Missing Dependencies**: Helpful setup instructions
5. **Unexpected Errors**: Caught and wrapped with context

### Testing

See `spec/unit/lint_command_spec.rb` for comprehensive tests.

Tests verify:
- Valid YAML returns success with stages and jobs
- Invalid syntax returns failure with error details
- Missing files return appropriate error
- Result object converts to hash correctly

## Future Commands

- **DagCommand**: Generate Graphviz DOT format (already implemented)
- **DryRunCommand**: Simulate pipeline execution
- **Other commands**: Follow same patterns
