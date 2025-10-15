# TODO - gitlab_ci_cli Issues and Improvements

## Critical Issues

### 1. ✅ RESOLVED: Array Include Path Handling
**Projects affected:** mesa, gstreamer
**Status:** RESOLVED - Both projects now pass all tests
**Resolution:** Include processor correctly handles array-type specifications

### 2. External Template Resolution
**Projects affected:** gitlab, gnome-builder
**Errors:**
- gitlab: Component authentication required (gitlab.com)
- gnome-builder: Component authentication required (gitlab.gnome.org)

**Root cause:** Projects reference external components requiring authentication
**Priority:** Medium
**Status:** Cannot fix without credentials - expected limitation
**Options:**
- Document limitation clearly
- Provide graceful error messages (already implemented)
- Support authentication tokens in future (if needed)

### 3. ✅ RESOLVED: YAML Extends/Anchors Jobs Missing Scripts
**Projects affected:** baserow, kicad, openrgb, veloren
**Status:** RESOLVED - All projects now pass lint and dry-run tests
**Resolution:** Implemented ExtendsResolver for proper template inheritance

## Medium Priority Issues

### 4. ✅ RESOLVED: Trigger Jobs Validation
**Project affected:** baserow, gstreamer
**Status:** RESOLVED - Trigger and pages jobs now recognized
**Resolution:** Added `trigger` and `pages` to valid job keywords in MockServer

### 5. ✅ RESOLVED: Template-Only Configurations
**Projects affected:** gitlab (Runner), kicad, veloren
**Status:** RESOLVED - Projects with templates now validate correctly
**Resolution:** Skip validation for template jobs (starting with '.')

## Test Results Summary

**Last Updated:** 2025-01-15

### Overall Pass Rates
- **Lint:** 9/11 (82%) - up from 3/11 (27%)
- **DAG:** 11/11 (100%)
- **Dry-Run:** 9/11 (82%) - up from 0/11 (0%)

### Passing All Tests (9/11 = 82%)
- ✓ baserow (959 lines)
- ✓ fdroid (854 lines)
- ✓ graphviz (1,397 lines)
- ✓ gstreamer (1,184 lines)
- ✓ inkscape (570 lines)
- ✓ kicad (23 lines)
- ✓ mesa (425 lines)
- ✓ openrgb (593 lines)
- ✓ veloren (45 lines)

### Failing (2/11)
| Project | Lint | DAG | Dry-Run | Main Issue |
|---------|------|-----|---------|------------|
| gitlab | ✗ | ✓ | ✗ | Component authentication required |
| gnome-builder | ✗ | ✓ | ✗ | Component authentication required |

**Note:** Both failures are due to external component authentication requirements, not implementation limitations.

## Code Quality Improvements (MPED Review)

### DAG Command Refactoring
**File:** `lib/commands/dag_command.rb`
**Priority:** Medium
**Status:** Functional but needs MPED improvements

Issues identified in MPED architecture review:

1. **Silent Failure for Invalid Stages** (Line 389-390)
   - **Issue:** Jobs referencing non-existent stages silently skip without error
   - **Code:** `job_stage_index = stages.index(job[:stage]); next unless job_stage_index && job_stage_index > 0`
   - **Fix needed:** Add explicit validation and fail-fast with clear error message
   - **MPED principle violated:** Fail Fast and Verbosely

2. **Missing Compound Graph Documentation** (Lines 316, 335, 397-402)
   - **Issue:** Compound graph implementation lacks documentation of tightly coupled requirements
   - **Details:** `compound=true`, invisible anchors, and `ltail` attributes must work together
   - **Fix needed:** Add comprehensive comment block explaining Graphviz compound graph design
   - **MPED principle violated:** Code Clarity and Maintainability

3. **Fragile Anchor Node String Construction** (Lines 335, 398)
   - **Issue:** Anchor node names built with string concatenation in two places
   - **Code:** `"__stage_anchor_#{sanitize_id(stage)}"` duplicated
   - **Fix needed:** Extract to `stage_anchor_id(stage)` helper method (single source of truth)
   - **MPED principle violated:** Single Source of Truth

4. **Undocumented Edge Data Structure** (Line 397-402)
   - **Issue:** Edge hash schema `{ from:, to:, ltail:, lhead:, style: }` defined implicitly
   - **Fix needed:** Document edge structure at top of `generate_dependency_edges` method
   - **MPED principle violated:** Data Design Before Algorithms

5. **Potential Empty Stage Cluster Bug** (Line 393-402)
   - **Issue:** May create edges to non-existent clusters if previous stage has no jobs
   - **Scenario:** Stage exists in `stages` array but has no jobs → no cluster created → dangling edge
   - **Fix needed:** Check that previous stage has jobs before creating stage-level edge
   - **MPED principle violated:** Fail Fast

6. **Edge Attribute Formatting Logic** (Lines 354-362)
   - **Issue:** Inline conditional logic for building edge attributes
   - **Fix needed:** Extract to `format_edge_attributes(edge)` helper method
   - **MPED principle violated:** Optimize for Readability First

**Recommendation:** Create follow-up issue/PR to address these MPED concerns while maintaining current functionality.

## Enhancements

### Include Processor Improvements
- [ ] Support for include arrays (not just single includes)
- [ ] Support for GitLab CI template catalog
- [ ] Support for remote project includes via GitLab API
- [ ] Better error messages for missing includes
- [ ] Support for conditional includes (rules)

### YAML Processing
- [ ] Implement `extends` keyword resolution
- [ ] Implement proper YAML anchor/alias expansion in job context
- [ ] Implement inheritance chain resolution (.job-template → job)

### Validation Improvements
- [ ] Recognize `trigger` jobs as valid
- [ ] Validate `trigger` job requirements
- [ ] Better handling of template-only configurations
- [ ] Support for `!reference` tag resolution
- [ ] Validate `needs` with artifacts/optional/project/ref

### Dry-Run Enhancements
- [ ] Support for parallel job execution simulation
- [ ] Support for job retry simulation
- [ ] Support for manual job triggering in simulation
- [ ] Better error reporting for configuration issues

### Local Job Execution
- [ ] **Run job locally with `run` command**
  - New command: `./bin/gitlab_ci_cli run <job_name> [options]`
  - Execute a specific job from .gitlab-ci.yml locally
  - Assume all tags and conditions match (bypass runner requirements)
  - Execute actual scripts, not simulation

- [ ] **Dependency control with `--run-deps` option**
  - `--run-deps=excl` (default): Run only the named job, excluding dependencies
  - `--run-deps=incl`: Run job WITH all its dependencies (needs + stage dependencies)
  - Dependencies executed in topologically sorted order
  - Fails fast if circular dependencies detected

- [ ] **Implementation requirements**
  - Parse job configuration (script, before_script, after_script)
  - Resolve job dependencies from `needs` and stage order
  - Perform topological sort for dependency execution order
  - Execute scripts in local shell environment
  - Support for job variables and variable expansion
  - Handle artifacts between dependent jobs (pass artifacts to next job)
  - Capture and display job output with timestamps
  - Exit with job's exit code (0 for success, non-zero for failure)

- [ ] **Additional options to consider**
  - `--dry-run`: Show execution plan without running scripts
  - `--shell=bash|sh|zsh`: Specify shell for script execution
  - `--workdir=<path>`: Set working directory for job execution
  - `--artifacts-dir=<path>`: Directory to store job artifacts
  - `--interactive`: Pause before each job for user confirmation

## Technical Debt

### Code Quality
- [ ] Add comprehensive unit tests for `IncludeProcessor`
- [ ] Add integration tests for include scenarios
- [ ] Add error handling tests for circular includes
- [ ] Document include resolution order and precedence

### Documentation
- [ ] Document supported include types
- [ ] Document known limitations with external templates
- [ ] Add examples of complex include scenarios
- [ ] Document extends resolution behavior

## Performance

- [ ] Cache fetched remote includes
- [ ] Optimize include tree resolution
- [ ] Add progress indicators for large include trees
- [ ] Consider lazy loading for unused includes

## Compatibility

### GitLab CI Features Not Yet Supported
- [ ] Component includes (GitLab 16.0+)
- [ ] Include with rules/conditions
- [ ] Dynamic child pipelines
- [ ] Multi-project pipelines
- [ ] Downstream pipelines
- [ ] Bridge jobs
- [ ] Environments with deployments

## Notes

**Current Support Level:**
- ✓ Local includes (repository-relative paths)
- ✓ Remote includes (HTTPS URLs)
- ✓ Template includes (when GitLab submodule available)
- ✓ Project includes (local filesystem only)
- ✗ Component includes (GitLab CI Catalog)
- ✗ Remote project includes (requires GitLab API)

**Known Limitations:**
1. Projects requiring external GitLab templates will fail unless gitlab submodule has templates
2. Projects using YAML extends need extends resolution implemented
3. Multi-project includes only work if projects exist on local filesystem
4. No support for GitLab CI Catalog components
