# Code Coverage Report

**Report Date:** 2025-10-14
**Coverage Tool:** SimpleCov 0.22
**Test Framework:** RSpec

## Summary

**Overall Line Coverage: 79.94% (813 / 1017 lines)**

**Status: FAIL - Below 90% threshold**

The codebase currently does not meet the 90% coverage threshold specified in todo.md.
We need to cover **103 additional lines** to reach 90% overall coverage.

## Coverage by Status

### Files Below 90% Coverage (5 files)

| File | Coverage | Lines Covered | Status |
|------|----------|---------------|--------|
| lib/include_processor.rb | 58.39% | 80 / 137 | Needs 44 more lines |
| lib/gitlab_ci_cli.rb | 62.59% | 87 / 139 | Needs 39 more lines |
| lib/commands/lint_command.rb | 63.57% | 89 / 140 | Needs 37 more lines |
| lib/runner_fleet.rb | 69.23% | 36 / 52 | Needs 11 more lines |
| lib/mock_pipeline.rb | 84.72% | 61 / 72 | Needs 4 more lines |

### Files At or Above 90% Coverage (8 files)

| File | Coverage | Lines Covered |
|------|----------|---------------|
| lib/mock_runner.rb | 100.00% | 32 / 32 |
| lib/child_pipeline_handler.rb | 100.00% | 42 / 42 |
| lib/version.rb | 100.00% | 2 / 2 |
| lib/variable_expander.rb | 98.00% | 49 / 50 |
| lib/mock_job.rb | 97.87% | 46 / 47 |
| lib/commands/dag_command.rb | 96.52% | 111 / 115 |
| lib/runner_exporter.rb | 94.74% | 72 / 76 |
| lib/mock_server.rb | 93.81% | 106 / 113 |

## Detailed Findings

### Critical: lib/include_processor.rb (58.39%)

**57 uncovered lines** - This file has the lowest coverage.

Uncovered lines include:
- Lines 86, 88, 90, 92, 94 (likely error handling or edge cases)
- Lines 126, 128 (validation logic)
- Lines 156, 164, 167, 170 (include type processing)
- Lines 178, 179, 183, 184, 187, 189 (include resolution)
- Lines 198, 201, 202 (and 37 more lines)

**Recommendation:** This module handles GitLab CI `include` directive processing, which is a complex feature with many edge cases. Priority should be:
1. Add tests for each include type (local, file, remote, template, project, component)
2. Test error conditions (missing files, circular includes, depth limits)
3. Test nested includes and merging logic

### Critical: lib/gitlab_ci_cli.rb (62.59%)

**52 uncovered lines** - The main CLI entry point.

Uncovered lines include:
- Lines 55, 58, 61-62, 64-65, 67-69 (CLI flag parsing)
- Lines 182, 185-188 (command routing)
- Lines 193-196, 201-202 (and 32 more lines)

**Recommendation:** This is the main entry point, so coverage gaps here indicate untested CLI paths:
1. Add integration tests for all CLI flag combinations
2. Test error handling for invalid flags
3. Test command routing for all subcommands
4. Test help and version output

### Critical: lib/commands/lint_command.rb (63.57%)

**51 uncovered lines** - Lint command implementation.

Uncovered lines include:
- Lines 107, 132, 138 (validation logic)
- Lines 159, 176, 191, 213 (output formatting)
- Lines 258, 264, 271 (error handling)
- Lines 283, 289, 294, 299 (and 31 more lines)

**Recommendation:** The lint command has multiple output formats and error paths:
1. Add tests for all output formats (text, JSON, JUnit)
2. Test error handling for invalid YAML
3. Test with various CI config edge cases
4. Test verbose mode output

### Moderate: lib/runner_fleet.rb (69.23%)

**16 uncovered lines** - Runner fleet management.

Uncovered lines: 23, 27, 49, 51, 54-55, 57, 60, 100, 104, 110, 114, 119, 123, 129, 133

**Recommendation:** Missing coverage for error conditions:
1. Add tests for invalid runner JSON formats
2. Test runner capacity exhaustion scenarios
3. Test tag matching edge cases
4. Test empty/missing runner directory

### Minor: lib/mock_pipeline.rb (84.72%)

**11 uncovered lines** - Pipeline state management.

Uncovered lines: 50-51, 54, 152-153, 160, 167, 180, 195-197

**Recommendation:** Close to threshold, needs:
1. Test pipeline state transitions
2. Test job dependency resolution edge cases
3. Test error conditions in pipeline execution

## Recommendations

### Immediate Actions (Priority Order)

1. **lib/include_processor.rb** - Add 44 lines of coverage
   - Test all 6 include types
   - Test depth limiting
   - Test circular dependency detection
   - Test error handling

2. **lib/gitlab_ci_cli.rb** - Add 39 lines of coverage
   - Add integration tests for all CLI flags
   - Test command routing
   - Test error messages

3. **lib/commands/lint_command.rb** - Add 37 lines of coverage
   - Test all output formats
   - Test error handling paths
   - Test edge cases in validation

4. **lib/runner_fleet.rb** - Add 11 lines of coverage
   - Test error conditions
   - Test edge cases

5. **lib/mock_pipeline.rb** - Add 4 lines of coverage
   - Test remaining state transitions

### Testing Strategy

The gaps in coverage indicate missing tests for:
- **Error handling paths** - Many uncovered lines are in error handling blocks
- **Edge cases** - Unusual input combinations aren't tested
- **Output formatting** - Alternative output formats lack coverage
- **CLI integration** - Command-line flag combinations aren't fully tested

### Next Steps

1. Add tests focusing on the 5 files below 90% coverage
2. Prioritize error handling and edge case scenarios
3. Add integration tests for CLI flag combinations
4. Re-run coverage after adding tests to verify improvement

### Configuration Note

SimpleCov is now configured in `spec/spec_helper.rb` with:
- Line coverage threshold: 90%
- Branch coverage threshold: 80%
- Current branch coverage: 60.47% (also needs improvement)

## Test Failures

Note: There are currently 3 failing integration tests unrelated to coverage:
- Missing --entry flag handling in dry-run command
- Missing --entry flag handling in dag command
- Missing --entry flag handling in lint command

These failures should be addressed as they indicate actual missing functionality for error handling.
