# Contributing to gitlab_ci_cli

Thank you for your interest in contributing to gitlab_ci_cli! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Code Style Guidelines](#code-style-guidelines)
- [Pull Request Process](#pull-request-process)
- [Updating GitLab Submodule](#updating-gitlab-submodule)
- [Project Architecture](#project-architecture)
- [Testing Strategy](#testing-strategy)

## Development Setup

### Prerequisites

Ensure you have Nix installed on your system. Installation instructions: https://nixos.org/download.html

### Initial Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/<you>/gitlab_local_ci.git
   cd gitlab_local_ci
   ```

2. Enter the dev shell (provides Ruby 3.3, Graphviz, just):
   ```bash
   nix develop
   ```

3. Initialize the GitLab submodule and install the gems:
   ```bash
   just setup
   ```

4. Verify the setup:
   ```bash
   just test
   just e2e
   ```

### Development Environment

The project uses Nix for reproducible dependency management. The dev shell is defined in `flake.nix` (`nix develop`; `shell.nix` remains for `nix-shell`) and provides Ruby 3.3, Git, Graphviz and just. See [docs/development.md](docs/development.md) for the gates.

### Justfile Commands

The project includes a `justfile` with helpful development commands:

```bash
just help              # List all available commands
just setup             # Initialize submodule and install dependencies
just test              # Run all tests
just test-file FILE    # Run specific test file
just lint              # Lint a YAML file
just dag               # Generate DAG visualization
just dry-run           # Run dry-run simulation
just clean             # Remove temporary files
just test-integration  # Run integration tests only
just update-gitlab     # Update GitLab submodule
```

## Running Tests

### Test Structure

Tests are organized in the `spec/` directory:

```
spec/
├── spec_helper.rb        # RSpec configuration
├── support/              # Test helpers and shared examples
├── fixtures/             # Test fixtures (YAML, JSON)
│   ├── yaml/            # Sample .gitlab-ci.yml files
│   └── runners/         # Sample runner configurations
├── unit/                 # Unit tests for individual components
└── integration/          # Integration tests for commands
```

### Running Tests

Run all tests (not `bundle exec rspec`: see the comment on the `test` recipe in the justfile):
```bash
just test
```

Run specific test file:
```bash
just test-file spec/unit/mock_server_spec.rb
```

Run integration tests only:
```bash
just test-integration
```

Coverage is measured on every `just test` run and must not drop below the ratchet in `spec/spec_helper.rb`. Golden outputs of `test_ci_projects/` are checked by `just e2e`; after an intended change run `just e2e-update` and review the diff.

### Writing Tests

Follow these guidelines when writing tests:

1. **Unit tests**: Test individual classes and methods in isolation
2. **Integration tests**: Test command-line interface and end-to-end workflows
3. **Fixtures**: Place test data in `spec/fixtures/`
4. **Mocking**: Mock external dependencies (GitLab API, file system when appropriate)
5. **Coverage**: Aim for 90%+ test coverage

Example test structure:
```ruby
RSpec.describe MockServer do
  let(:gitlab_path) { File.expand_path('../../gitlab', __dir__) }
  let(:server) { described_class.new(gitlab_path: gitlab_path) }

  describe '#create_pipeline' do
    it 'creates a valid pipeline from YAML config' do
      config = File.read('spec/fixtures/yaml/valid_simple.yml')
      pipeline = server.create_pipeline(config: config, ref: 'main')

      expect(pipeline).to be_valid
      expect(pipeline.jobs.count).to eq(3)
    end
  end
end
```

## Code Style Guidelines

### Ruby Style

This project follows standard Ruby conventions:

- Use 2 spaces for indentation (not tabs)
- Maximum line length: 120 characters
- Use snake_case for methods and variables
- Use CamelCase for classes and modules
- Use descriptive names for variables and methods
- Add comments for complex logic

### Code Organization

- Keep classes focused on a single responsibility
- Extract complex logic into separate methods
- Use modules for shared behavior
- Avoid circular dependencies

### Documentation

- Add YARD documentation comments for public APIs
- Document method parameters and return values
- Include usage examples for complex methods
- Update README.md when adding new features

Example YARD documentation:
```ruby
# Creates a new pipeline from the given configuration
#
# @param config [String] YAML configuration content
# @param ref [String] Git reference to simulate
# @param variables [Hash] CI variables to inject
# @return [Pipeline] The created pipeline object
# @raise [ConfigError] If configuration is invalid
def create_pipeline(config:, ref: 'HEAD', variables: {})
  # Implementation
end
```

### Commit Messages

Write clear, descriptive commit messages:

- Use present tense ("Add feature" not "Added feature")
- Start with a verb ("Fix", "Add", "Update", "Remove", etc.)
- Keep first line under 72 characters
- Add detailed description in commit body if needed

Example:
```
Add support for child pipeline triggers

Implements ChildPipelineHandler to recursively invoke
gitlab_ci_cli for downstream pipelines. Variables are
propagated from parent to child pipeline.

Closes #42
```

## Pull Request Process

### Before Submitting

1. Ensure all tests pass:
   ```bash
   just test
   ```

2. Verify your changes work with actual GitLab CI files:
   ```bash
   just lint path/to/.gitlab-ci.yml
   just dry-run path/to/.gitlab-ci.yml
   ```

3. Update documentation if you've added or changed features

4. Add or update tests for your changes

### Submitting a Pull Request

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes and commit them:
   ```bash
   git add .
   git commit -m "Add your feature"
   ```

3. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

4. Open a Pull Request on GitHub with:
   - Clear title describing the change
   - Description of what changed and why
   - Reference to any related issues
   - Screenshots/examples if applicable

### Pull Request Checklist

- [ ] Tests pass locally
- [ ] New tests added for new functionality
- [ ] Documentation updated (README.md, code comments)
- [ ] Commit messages are clear and descriptive
- [ ] No patches to GitLab submodule (maintain zero-patch policy)
- [ ] Code follows style guidelines
- [ ] Integration tests pass against multiple GitLab versions

### Review Process

- Maintainers will review your PR and may request changes
- Address feedback by pushing additional commits to your branch
- Once approved, a maintainer will merge your PR

## Updating GitLab Submodule

The GitLab submodule is pinned to a specific version for stability. When updating:

### Quick Update

Use the justfile command:
```bash
just update-gitlab
```

This will:
1. Fetch the latest tags
2. Check out the latest stable version
3. Stage the submodule change

### Manual Update

1. Navigate to the submodule:
   ```bash
   cd gitlab
   ```

2. Fetch latest changes:
   ```bash
   git fetch --tags
   ```

3. List available versions:
   ```bash
   git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V
   ```

4. Checkout desired version:
   ```bash
   git checkout v17.0.0
   ```

5. Return to main project and commit:
   ```bash
   cd ..
   git add gitlab
   git commit -m "Update GitLab submodule to v17.0.0"
   ```

### Testing Submodule Updates

After updating the GitLab submodule:

1. Run the test suite:
   ```bash
   just test
   ```

2. Test against real GitLab CI files:
   ```bash
   just lint examples/.gitlab-ci.yml
   just dry-run examples/.gitlab-ci.yml
   ```

3. Check for API changes:
   - Review GitLab changelog for breaking changes
   - Update wrapper code if necessary
   - Update compatibility matrix in README.md

### Version Compatibility Matrix

When updating the submodule, update the compatibility table in README.md:

```markdown
| GitLab Version | Status | Notes |
|---------------|--------|-------|
| 17.x | Tested | Current |
| 16.x | Tested | LTS |
| 15.x | Tested | Minimum |
```

## Project Architecture

Understanding the architecture helps with contributions:

### Three-Module Design

1. **MockServer** (`lib/mock_server.rb`):
   - Wraps GitLab's YAML processor and pipeline services
   - Intercepts runner API calls
   - Emits events for job scheduling

2. **RunnerFleet** (`lib/runner_fleet.rb`):
   - Loads runner configurations from JSON
   - Matches jobs to eligible runners
   - Tracks runner capacity

3. **MockRunner** (`lib/mock_runner.rb`):
   - Simulates runner behavior
   - Logs job details
   - Emits job state transitions

### Zero-Patch Policy

**Critical Rule**: Never modify files in the `gitlab/` submodule directory.

Instead:
- Create wrapper classes in `lib/`
- Use monkey-patching if absolutely necessary (document thoroughly)
- Intercept at defined extension points

This ensures easy upstream tracking and GitLab version updates.

### Event-Driven Architecture

The tool uses events to decouple components:

```ruby
# Emit event
emit_event(:job_assigned, {
  job_id: job.id,
  runner_id: runner.id,
  payload: build_payload(job)
})

# Handle event
def handle_job_assignment(event)
  # Process job
end
```

## Testing Strategy

### Unit Tests

Test individual components in isolation:
- Mock external dependencies
- Test edge cases and error handling
- Test public API contracts

### Integration Tests

Test end-to-end workflows:
- Test CLI commands
- Use real fixture files
- Test against actual GitLab submodule code

### GitLab Version Matrix Testing

Test against multiple GitLab versions:
- Maintain compatibility with 15.x, 16.x, 17.x
- Run tests against each supported version
- Document known issues or limitations

### Performance Testing

For large pipelines:
- Benchmark parsing time for large YAML files
- Test runner matching with large fleets
- Profile memory usage

## Getting Help

- Open an issue for bug reports or feature requests
- Ask questions in discussions
- Review existing issues and PRs for context

## Code of Conduct

- Be respectful and professional
- Welcome newcomers and help them get started
- Focus on constructive feedback
- Follow GitHub's community guidelines

Thank you for contributing to gitlab_ci_cli!
