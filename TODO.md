# TODO - gitlab_ci_cli Issues and Improvements

## Critical Issues

### 1. Array Include Path Handling
**Projects affected:** mesa, gstreamer
**Error:** `undefined method 'start_with?' for an instance of Array`
**Root cause:** Include processor doesn't handle array-type include specifications
**Priority:** High
**Fix needed:** Update `IncludeProcessor#fetch_local_include` to handle arrays of paths

### 2. External Template Resolution
**Projects affected:** gitlab, gnome-builder
**Errors:**
- gitlab: `GitLab CI template not found: Jobs/Dependency-Scanning.latest.gitlab-ci.yml`
- gnome-builder: `Project not found: gnome/citemplates`

**Root cause:** Projects reference external GitLab templates and other projects that aren't available locally
**Priority:** Medium
**Options:**
- Add support for GitLab template catalog
- Add fallback mechanism for missing templates
- Document limitation and provide graceful degradation

### 3. YAML Extends/Anchors Jobs Missing Scripts
**Projects affected:** baserow, kicad, openrgb, veloren
**Error:** Multiple jobs flagged as `missing required 'script' field`
**Root cause:** Jobs use `extends:` to inherit script from templates, but validation runs before extends resolution
**Priority:** Medium
**Fix needed:** Implement proper extends resolution before job validation

## Medium Priority Issues

### 4. Trigger Jobs Validation
**Project affected:** baserow
**Error:** `Job 'trigger-saas-build' has unknown key: 'trigger'`
**Root cause:** Validation doesn't recognize `trigger` as valid alternative to `script`
**Priority:** Medium
**Fix needed:** Update `LintCommand::VALID_JOB_KEYWORDS` to include trigger-specific keys

### 5. Template-Only Configurations
**Projects affected:** gitlab (Runner), kicad, veloren
**Error:** `No jobs defined in configuration`
**Root cause:** Some CI files only define templates/includes with no concrete jobs
**Priority:** Low
**Fix needed:** Better handling of template-only configurations (maybe just warnings instead of errors)

## Test Results Summary

### Passing All Tests (3/11 = 27%)
- ✓ fdroid (854 lines)
- ✓ graphviz (1,397 lines)
- ✓ inkscape (570 lines)

### Partial Pass (4/11)
| Project | Lint | DAG | Dry-Run | Main Issue |
|---------|------|-----|---------|------------|
| baserow | ✗ | ✓ | ✗ | Missing scripts (extends not resolved) |
| kicad | ✗ | ✓ | ✗ | Missing scripts (extends not resolved) |
| openrgb | ✗ | ✓ | ✗ | Missing scripts (extends not resolved) |
| veloren | ✗ | ✓ | ✗ | Missing scripts (extends not resolved) |

### Failing Multiple Tests (4/11)
| Project | Lint | DAG | Dry-Run | Main Issue |
|---------|------|-----|---------|------------|
| gitlab | ✗ | ✗ | ✗ | Missing GitLab templates |
| gnome-builder | ✗ | ✗ | ✗ | External project reference |
| gstreamer | ✗ | ✗ | ✗ | Array include handling |
| mesa | ✗ | ✗ | ✗ | Array include handling |

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
