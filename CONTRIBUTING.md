# Contributing to gitlab_ci_cli

Thank you for your interest in contributing to gitlab_ci_cli! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Code Style Guidelines](#code-style-guidelines)
- [Pull Request Process](#pull-request-process)
- [Updating GitLab Submodule](#updating-gitlab-submodule)
- [Project Architecture](#project-architecture)

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
just update-gitlab     # Update GitLab submodule (not working yet, see below)
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

Prefer specs that go through `PipelineBuilder` or the CLI, and compare the
result with what upstream GitLab does (cite the upstream file you checked).
Specs that evaluate rules must pin the pipeline context with
`spec/support/pinned_pipeline_context.rb`, so they pass on any branch. Each
fix should come with a spec that fails without it. Existing examples:
`spec/unit/pipeline_builder_defaults_spec.rb`,
`spec/integration/pipeline_parity_spec.rb`.

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

`gitlab/` is the upstream reference: a checkout of a GitLab release tag. `just update-gitlab` does not work yet (it only re-reads the current
tag); update by hand:

```bash
git -C gitlab ls-remote --tags origin | grep -E 'v[0-9]+\.[0-9]+\.[0-9]+-ee$' | sort -V -k2 | tail -1
git -C gitlab fetch --depth 1 origin tag vX.Y.Z-ee
git -C gitlab checkout vX.Y.Z-ee
just test && just e2e          # keyword/variable drift specs read the submodule
git add gitlab && git commit -m "chore: bump gitlab reference to vX.Y.Z-ee"
```

Then check what changed upstream in the areas the tool ports
(`lib/gitlab/ci/config`, `lib/gitlab/ci/build/rules`,
`lib/gitlab/ci/variables`, `lib/gitlab/ci/pipeline/expression`) and file
tasks for new behaviour.

## Project Architecture

See [docs/architecture.md](docs/architecture.md): one `PipelineBuilder`
runs GitLab's pipeline-construction steps in GitLab's order, and every
command uses it. Never patch the `gitlab/` submodule.

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
