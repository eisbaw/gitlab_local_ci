# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed (breaking)
- `run` and `export-just` recipes no longer pass the whole host environment
  to jobs. A job sees its GitLab variables plus only `PATH`, `HOME`, `USER`,
  `LOGNAME`, `SHELL`, `LANG`, `LC_*`, `TERM`, `TZ` and `TMPDIR`, so host
  `CI_*`/`GITLAB_*` values (e.g. when the tool runs inside a CI job) no
  longer shadow the simulated ones. New `--pass-env NAME[,NAME...]` adds
  names; `--pass-env all` restores the old behaviour. `export-just` writes
  the mode into the recipes: regenerate exported justfiles.
- `export-just --shell` was removed: it was accepted but never read.
  Recipes are shebang recipes run by `bash`; drop the flag from scripts
  that pass it (it is now `Unknown flag: --shell`).
- `export-just` recipe names for colliding job names changed. Before, the
  first job (config order) kept the bare name and later ones got `-2`,
  `-3`, ...; reordering jobs silently changed which job a name ran. Now
  every job of a collision set gets `_<6 hex digits of SHA-256 of the job
  name>` (`a b` -> `a_b_c8687a`) and none keeps the bare name. Regenerate
  exported justfiles and update callers that used `-2`-style names; run
  `just --list` to see the new ones. Non-colliding names are unchanged.
- `--pipeline` takes upstream source names (`merge_request_event`, `web`,
  ...); `merge_request` and `manual` remain as aliases.
- `lint` no longer lists or counts hidden (`.name`) templates as jobs.

### Changed
- One pipeline builder for every command, following GitLab v19.5.3
  (`gitlab/` submodule): includes (main file wins, later include wins),
  `extends` (child arrays replace), `!reference`, `default:`/`inherit:`,
  `parallel`/`parallel:matrix`, `.pre`/`.post`, stage ordering in dry-run,
  predefined variables per pipeline type (unset, not empty), and rules.
- `run` gives a job GitLab's environment, a separate `after_script` shell
  with `CI_JOB_STATUS`, `pipefail` and the job's exit code; `export-just`
  writes one shebang recipe per job doing the same.
- A dry-run that cannot finish exits 1 and names the reason per job.

### Security
- A component host, and every redirect hop of a project, component or
  template download, was connected to without an address check:
  `component: 127.0.0.1:18443/g/c@1.0` reached loopback, and a public host
  could redirect to 169.254.169.254. These now get the `include: remote`
  check and pinning before connecting (one implementation,
  `lib/public_address.rb`). Only your GitLab instance (`CI_SERVER_URL` /
  `origin`), same host and port, is exempt.
- A component reference with `..` in its project path
  (`evil.example/a/../../../../tmp/pwn@v1`) read a `template.yml` from, and
  wrote the downloaded one to, a path outside `ext_tmp/`. Every cache path
  (templates, projects, components; read and write) is now built in one
  place that refuses `..`, `.`, empty segments, NUL and backslashes and
  asserts the result stays under the cache root.
- `$CI_SERVER_URL`, `$CI_SERVER_HOST` and `$CI_SERVER_FQDN` in an include
  path were read from the tool's own environment, so running it inside a
  CI job on another instance changed which host a component was fetched
  from. They now come from `--variables`, else the instance `include:
  project` uses (`origin` host, else gitlab.com).
- `include: project` requested a file not found next to the project from
  gitlab.com, gitlab.gnome.org and gitlab.freedesktop.org in turn, sending
  a private project path to unrelated hosts. It now asks one instance:
  `--variables CI_SERVER_URL`, else the `origin` remote's host, else
  gitlab.com. The download cache is now per instance
  (`ext_tmp/projects/<host>/...`); files cached before are fetched again.
  A repository whose `origin` is not a GitLab host needs
  `--variables CI_SERVER_URL=...` for project includes.
- `include: project` read from a sibling checkout now warns that `ref:` is
  not honoured, and a read error there is reported instead of silently
  falling back to the network. A `ref:` containing `..` is rejected.
- `include: remote` checked only the first address a host resolved to, and
  only against IPv4 ranges: `https://localhost:9/` (resolving to `::1`) or an
  answer mixing a public and a private address got through. Every address
  is now checked, IPv6 and IPv4-mapped ones included, literal IP hosts too,
  and the connection goes to the checked address (no DNS rebinding window).
- `export-just`: a newline in a job name, stage or tag could add recipes or
  assignments to the generated justfile, and an assignment ran when any
  recipe was invoked. Config text is now escaped wherever it lands outside
  the quoted recipe body.
- `CI_PROJECT_PATH` could contain part of a password from a malformed
  `origin` URL; such URLs now fall back to the directory name.

### Earlier unreleased work

Recorded in October 2025 and kept as history. Several items no longer
hold: child-pipeline execution and the runner exporter are not reachable
from any command; `--undefined` has no effect; the docs listed under
"Comprehensive documentation suite" were replaced (the old ones are in
`cruft/docs-2025/`); the CLI needs no gems at run time, but the
development Gemfile and dev shell are not dependency-free; the example
count and speed figures are from that time.

### Added
- Fail-fast validation with enhanced error context for pipeline configuration issues
- Error context improvements providing clearer diagnostic information
- Performance benchmarking test suite for large-scale pipeline testing
- Benchmarks for 100-job and 1000-job pipeline processing
- Benchmarks for runner fleet scaling (10 and 100 runners)
- Comprehensive test suite with 476 passing examples
- Support for GitLab CI `include:` directive processing
- Include types: local, file, remote, template, project, component
- Maximum include depth protection (150 levels)
- Child pipeline triggering support via `trigger:` keyword
- Parent variable passing to child pipelines
- Recursive child pipeline execution
- Runner exporter tool for GitLab API integration
- Export runner configurations from production GitLab instances to JSON
- DAG visualization via Graphviz DOT output
- Pipeline dependency graph generation with stage grouping
- Circular dependency detection in job `needs:` relationships
- Multiple output formats: text, JSON, JUnit XML
- Formatter factory for extensible output formatting
- Variable expansion with configurable undefined variable handling
- Three modes: warning, error, empty string replacement
- Support for `${VAR}` and `$VAR` syntax
- Mock runner fleet simulation
- Tag-based job matching
- Runner capacity management and concurrency limits
- Runner tag compatibility checking
- Comprehensive documentation suite
- README.md with quick start guide and usage examples
- CONTRIBUTING.md with development guidelines
- docs/event_schema.md for event system reference
- docs/runner_format.md for runner JSON configuration
- License file (Apache 2.0)

### Changed
- Refactored to standalone architecture without GitLab gem dependencies
- Pure Ruby + YAML parsing using stdlib only
- 8-12x faster validation (0.3s vs 3s+ with GitLab gems)
- Zero external dependencies beyond Ruby stdlib
- No gem compilation or native dependencies required
- Eliminated duplicate state tracking in pipeline management
- Moved pipeline status tracking from MockServer to MockPipeline
- Single source of truth for job states driving pipeline status computation
- Improved encapsulation with self-contained pipeline objects
- Consolidated documentation from multiple arch files into README.md
- Removed outdated architecture documentation in favor of inline documentation

### Fixed
- Critical shell injection vulnerability in child pipeline handler
- Replaced backtick shell execution with `Open3.capture2e`
- Prevented command injection via child pipeline arguments
- Critical SSRF (Server-Side Request Forgery) vulnerabilities in remote includes
- Added comprehensive URL validation for remote include processing
- Enforced HTTPS-only for remote includes
- Added private IP range validation (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- Blocked loopback (127.0.0.0/8) and link-local (169.254.0.0/16) addresses
- Added DNS resolution with private IP detection
- Implemented connection timeouts (5s read, 3s connect)
- Enabled SSL certificate verification (VERIFY_PEER)
- Runner tag matching logic
- Fail-fast error handling for invalid configurations
- 85 failing tests (79% failure reduction)
- Runner concurrency limit enforcement
- Job state transition handling

### Security
- **CRITICAL**: Fixed shell injection vulnerability in `ChildPipelineHandler` 
  - Impact: Arbitrary command execution via crafted child pipeline arguments
  - Mitigation: Switched from backtick to safe `Open3.capture2e` with argument array
  - All child pipeline arguments now passed directly without shell interpolation
- **CRITICAL**: Fixed SSRF vulnerability in `IncludeProcessor` 
  - Impact: Access to internal network services via malicious remote includes
  - Mitigation: Comprehensive URL validation and private IP blocking
  - Added domain allowlist support via `GITLAB_CI_ALLOWED_DOMAINS` environment variable
  - Note: DNS rebinding attacks remain a known limitation in Ruby stdlib
- Enhanced input validation for file paths
- Improved error messages without exposing sensitive system information

## [0.1.0] - 2025-10-14

### Added
- Initial release of gitlab_ci_cli
- Local GitLab CI pipeline simulation without GitLab server
- Three core commands: `lint`, `dag`, `dry-run`
- Lint command for YAML validation
  - Validates YAML syntax using Psych parser
  - Validates job structure (script, stage, needs, extends)
  - Validates stage references
  - Detects circular dependencies
  - Validates extends references
  - Validates script format (array or string)
- DAG command for pipeline visualization
  - Generates Graphviz DOT format output
  - Stage-grouped job visualization
  - Dependency edge rendering for `needs:` relationships
- Dry-run command for pipeline simulation
  - Time-based job scheduling simulation
  - Runner assignment based on tags and capacity
  - Job lifecycle state transitions (pending → running → completed)
  - Pipeline completion status reporting
- Mock GitLab server implementation
  - Direct YAML parsing without GitLab classes
  - Job extraction and validation
  - Event-driven architecture
  - Pipeline state management
- Mock runner fleet manager
  - JSON-based runner configuration
  - Tag-based job matching
  - Capacity tracking and management
  - Support for multiple executor types (shell, docker)
- Mock runner client
  - Job receipt simulation
  - Event logging for job lifecycle
  - Concurrent job handling
- Nix-based development environment
  - Reproducible dependency management via shell.nix
  - Ruby 3.0+ runtime
  - Graphviz for DAG visualization
  - Just command runner for workflow automation
  - RSpec for testing
- Justfile with development commands
  - `just test` - Run test suite
  - `just lint` - Validate YAML files
  - `just dag` - Generate pipeline visualization
  - `just dry-run` - Simulate pipeline execution
  - `just setup` - Initialize project dependencies
  - `just clean` - Remove temporary files
- Test infrastructure
  - Unit tests for all core modules
  - Integration tests for command workflows
  - Fixture-based testing with example YAML files
  - Example runner configurations
- GitLab v17.5.0-ee as git submodule reference
- Apache 2.0 license

### Performance
- Cold start: ~0.3 seconds (vs 2.5-3.5s with GitLab gems)
- Warm start: ~0.3 seconds
- Zero gem installation time
- Minimal memory footprint (no Rails overhead)
- Support for pipelines with up to 1000 jobs
- Support for runner fleets up to 100 runners

### Compatibility
- Ruby 3.0+ required
- Platform support: Linux, macOS, Windows (via WSL)
- GitLab CI YAML syntax compatibility with GitLab 15.0-17.5
- Nix package manager required for reproducible builds

## Project Inception

### [0.0.0] - 2025-10-13
- Project initialized with PRD (Product Requirements Document)
- Defined three-module architecture: MockServer, RunnerFleet, MockRunner
- Established zero-patch policy for GitLab integration
- Set up git repository structure
- Added GitLab CE as unmodified git submodule

---

## Migration Notes

### Upgrading from GitLab Gem-based Validation

If you were previously using GitLab gems for CI validation, note these changes:

1. **No GitLab gems required**: Remove `gitlab` gem from your Gemfile
2. **Faster execution**: Expect 8-12x faster validation times
3. **Standalone operation**: No GitLab server or API access needed
4. **Limitations**: Advanced `rules:` expressions and complex variable expansions not yet supported

### Runner Configuration Format

Runner JSON files should follow this minimal format:

```json
{
  "id": "runner-1",
  "tags": ["docker", "linux"],
  "executor": "shell",
  "max_jobs": 2
}
```

Place runner JSON files in `./runners/` directory or specify custom path with `--runners` flag.

---

## Development Philosophy

This project follows MPED architectural principles:

- **Fundamentals First**: Reproducible infrastructure via Nix, zero external dependencies
- **Composable Design**: Libraries over frameworks, modules compose upwards
- **Data Design**: Single source of truth, no duplicate state, computed derived views
- **Fail Fast**: Clear error messages, verbose failures, comprehensive validation
- **Optimize for Readability**: Code for humans first, optimize after profiling

---

## Links

- [Homepage](https://github.com/eisbaw/gitlab_local_ci)
- [Documentation](./README.md)
- [Contributing Guidelines](./CONTRIBUTING.md)
- [Issue Tracker](https://github.com/eisbaw/gitlab_local_ci/issues)
- [License](./LICENSE)

---

## Versioning Policy

This project uses [Semantic Versioning](https://semver.org/):

- **MAJOR**: Incompatible API changes or breaking changes to CLI interface
- **MINOR**: New features added in backwards-compatible manner
- **PATCH**: Backwards-compatible bug fixes and security patches

Security fixes are released as PATCH versions and noted in the Security section.

---

## Security Disclosures

See [SECURITY.md](SECURITY.md) for how to report a vulnerability. Security fixes are listed in the Security section of each release.

