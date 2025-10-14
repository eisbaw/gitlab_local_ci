# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup with Nix environment
- GitLab CE submodule integration (zero-patch policy)
- Three-module architecture (MockServer, RunnerFleet, MockRunner)
- CLI interface with lint, dag, and dry-run commands
- YAML parsing and validation using upstream GitLab code
- DAG visualization with Graphviz DOT output
- Pipeline simulation with mock runner fleet
- Runner fleet management with JSON configuration
- Variable handling with configurable undefined modes (warning/error/empty)
- Support for CI variables via --variables and --env flags
- Multiple output formats (text, JSON, JUnit)
- Justfile with development workflow commands
- Comprehensive test suite (unit and integration tests)
- GitLab version compatibility (15.x, 16.x, 17.x)

### Changed
- None

### Deprecated
- None

### Removed
- None

### Fixed
- None

### Security
- None

## [0.1.0] - 2025-10-13

### Added
- Project initialization
- Basic project structure (lib/, spec/, bin/, runners/)
- Nix shell environment with all dependencies
- GitLab submodule integration
- Development tooling (RSpec, Bundler, Just)
- Git configuration (.gitignore, .gitmodules)
- Core executable scaffold
- Test infrastructure and fixtures
- Documentation files (README.md, LICENSE, CONTRIBUTING.md, CHANGELOG.md)

[Unreleased]: https://github.com/your-org/gitlab_ci_cli/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/your-org/gitlab_ci_cli/releases/tag/v0.1.0
