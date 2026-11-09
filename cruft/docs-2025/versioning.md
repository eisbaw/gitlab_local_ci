# Versioning Strategy

This document defines the versioning, tagging, and release strategy for `gitlab_ci_cli`.

## Table of Contents

1. [Semantic Versioning](#semantic-versioning)
2. [Version Number Format](#version-number-format)
3. [Git Tagging Conventions](#git-tagging-conventions)
4. [Version Number Locations](#version-number-locations)
5. [Release Branch Strategy](#release-branch-strategy)
6. [GitLab CI/CD Compatibility](#gitlab-cicd-compatibility)
7. [Version Bump Guidelines](#version-bump-guidelines)
8. [Release Process](#release-process)

---

## Semantic Versioning

This project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

Version format: **MAJOR.MINOR.PATCH**

Example: `1.2.3`

### MAJOR Version (Breaking Changes)

Increment when making **incompatible changes** that break existing functionality:

- CLI command removal or renaming (e.g., `lint` → `validate`)
- CLI option removal or incompatible changes (e.g., removing `--entry` flag)
- Output format changes that break parsing (e.g., changing JSON structure)
- Minimum Ruby version requirement increase (e.g., Ruby 3.0 → 3.2)
- Runner configuration format breaking changes
- Removal of deprecated features

**Examples:**
- `0.9.0` → `1.0.0`: Initial stable release with stabilized API
- `1.3.5` → `2.0.0`: Remove deprecated `--gitlab-dir` option
- `2.1.0` → `3.0.0`: Change JSON output structure for lint command

**Policy:** Major version 0.x indicates pre-release/unstable. Breaking changes are allowed without major version bump in 0.x releases.

### MINOR Version (New Features)

Increment when adding **backward-compatible functionality**:

- New CLI commands (e.g., adding `export-runners` command)
- New CLI options that don't break existing usage
- New output formats (e.g., adding YAML output alongside JSON/text)
- New validation rules or linting checks (non-breaking)
- Enhanced error messages or logging
- Performance improvements
- Support for new GitLab CI features (e.g., parallel matrix support)
- Non-breaking runner configuration additions

**Examples:**
- `1.0.0` → `1.1.0`: Add `include` file processing support
- `1.1.0` → `1.2.0`: Add `--format yaml` output option
- `1.2.0` → `1.3.0`: Add support for GitLab CI `parallel:matrix` syntax

**Policy:** Minor versions maintain backward compatibility. Existing scripts and integrations continue working without modification.

### PATCH Version (Bug Fixes)

Increment when making **backward-compatible bug fixes**:

- Fixing incorrect validation logic
- Correcting circular dependency detection
- Fixing DAG visualization errors
- Typo fixes in help text or error messages
- Performance optimizations without API changes
- Documentation corrections (typos, clarity)
- Test improvements
- Internal refactoring with no external impact

**Examples:**
- `1.2.0` → `1.2.1`: Fix circular dependency false positive
- `1.2.1` → `1.2.2`: Correct YAML parsing edge case
- `1.2.2` → `1.2.3`: Fix DAG generation for jobs without stages

**Policy:** Patch versions are always safe to update. They fix defects without changing behavior.

---

## Version Number Format

### Standard Format

```
MAJOR.MINOR.PATCH
```

Examples: `0.1.0`, `1.0.0`, `1.2.3`

### Pre-release Versions (Optional)

For pre-release versions, append a hyphen and identifier:

```
MAJOR.MINOR.PATCH-IDENTIFIER
```

Identifiers:
- `alpha.N` - Early development, unstable
- `beta.N` - Feature complete, testing phase
- `rc.N` - Release candidate, final testing

Examples:
- `1.0.0-alpha.1` - First alpha release
- `1.0.0-beta.2` - Second beta release
- `1.0.0-rc.1` - First release candidate
- `1.0.0` - Final stable release

**Policy:** Pre-release versions are not recommended for production use.

---

## Git Tagging Conventions

### Tag Format

All version tags MUST follow this format:

```
vMAJOR.MINOR.PATCH
```

Examples: `v0.1.0`, `v1.0.0`, `v1.2.3`

The `v` prefix is mandatory for consistency with tooling and GitLab conventions.

### Annotated vs Lightweight Tags

**Always use annotated tags for releases:**

```bash
# Correct: Annotated tag with message
git tag -a v1.2.3 -m "Release v1.2.3: Add include file support"

# Incorrect: Lightweight tag (no message)
git tag v1.2.3
```

**Rationale:** Annotated tags:
- Include tagger name, email, and timestamp
- Support GPG signing for verification
- Appear in `git describe` output
- Are pushed by default with `git push --follow-tags`

### Tag Message Format

Tag messages should be concise and descriptive:

```
Release vMAJOR.MINOR.PATCH: Brief description

Optional longer description of key changes.
```

**Examples:**

```bash
# Patch release
git tag -a v1.2.3 -m "Release v1.2.3: Fix circular dependency detection"

# Minor release
git tag -a v1.3.0 -m "Release v1.3.0: Add include file processing support"

# Major release
git tag -a v2.0.0 -m "Release v2.0.0: Stable API with breaking changes

- Remove deprecated --gitlab-dir option
- Change JSON output structure for lint command
- Require Ruby 3.2+
"
```

### Creating Tags

```bash
# 1. Update version in lib/version.rb
# 2. Update CHANGELOG.md
# 3. Commit changes
git add lib/version.rb CHANGELOG.md
git commit -m "chore: Bump version to v1.2.3"

# 4. Create annotated tag
git tag -a v1.2.3 -m "Release v1.2.3: Fix circular dependency detection"

# 5. Push commit and tag
git push origin master
git push origin v1.2.3

# Alternative: Push all annotated tags
git push --follow-tags
```

### Tag Signing (Optional but Recommended)

Sign tags with GPG for verification:

```bash
git tag -s v1.2.3 -m "Release v1.2.3: Fix circular dependency detection"
```

Verify signature:

```bash
git tag -v v1.2.3
```

---

## Version Number Locations

Version numbers must be updated in the following locations:

### 1. `lib/version.rb` (Primary Source of Truth)

This is the **single source of truth** for the current version.

```ruby
# lib/version.rb
# frozen_string_literal: true

module GitlabCiCli
  VERSION = '1.2.3'
end
```

**Policy:** All other version references derive from this constant.

### 2. `CHANGELOG.md`

Update the changelog before each release:

```markdown
## [1.2.3] - 2025-10-15

### Fixed
- Circular dependency detection edge case
- DAG visualization for implicit stages

[1.2.3]: https://github.com/your-org/gitlab_ci_cli/releases/tag/v1.2.3
```

**Format:** Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) conventions.

### 3. Documentation References

Update version references in documentation when behavior changes:

- `README.md` - Update feature compatibility notes
- `docs/architecture.md` - Update if architectural changes occur
- `docs/upgrade_guide.md` - Add upgrade notes for breaking changes

**Policy:** Don't update documentation for every patch release. Only update when functionality changes affect documented behavior.

### 4. Git Tags

Tag the release commit with the version number:

```bash
git tag -a v1.2.3 -m "Release v1.2.3: Brief description"
```

---

## Release Branch Strategy

This project uses a **trunk-based development** model with minimal branching.

### Development Flow

```
master (main branch)
  ├── Feature branches
  ├── Bugfix branches
  └── Release tags
```

### Branch Structure

#### Master Branch

- **Purpose:** Main development branch
- **Status:** Should always be stable and releasable
- **Protection:** Protected, requires PR reviews
- **Commits:** All features and fixes merge here

Development workflow:

```bash
# Create feature branch
git checkout -b feature/include-processing

# Make changes, commit
git add .
git commit -m "feat: Add include file processing"

# Push and create PR
git push origin feature/include-processing
# Open pull request to master
```

#### Release Tags (Not Branches)

Instead of long-lived release branches, use **tags** to mark releases:

```bash
# Tag a release on master
git checkout master
git pull
git tag -a v1.2.3 -m "Release v1.2.3: Fix circular dependency detection"
git push origin v1.2.3
```

**Rationale:** Trunk-based development with tags:
- Simplifies branch management
- Reduces merge conflicts
- Encourages continuous integration
- Aligns with modern Git workflows

#### Feature Branches

- **Naming:** `feature/description` or `feat/description`
- **Lifetime:** Short-lived, deleted after merge
- **Examples:** `feature/include-processing`, `feat/matrix-support`

#### Bugfix Branches

- **Naming:** `fix/description` or `bugfix/description`
- **Lifetime:** Short-lived, deleted after merge
- **Examples:** `fix/circular-dependency`, `bugfix/dag-rendering`

### Hotfix Strategy

For urgent production fixes:

```bash
# 1. Create hotfix branch from latest release tag
git checkout -b hotfix/critical-bug v1.2.3

# 2. Fix the bug
git add .
git commit -m "fix: Critical bug in validation logic"

# 3. Merge to master
git checkout master
git merge --no-ff hotfix/critical-bug

# 4. Update version to v1.2.4
# Edit lib/version.rb and CHANGELOG.md

# 5. Tag new patch release
git tag -a v1.2.4 -m "Release v1.2.4: Critical validation fix"

# 6. Push changes and tag
git push origin master v1.2.4

# 7. Delete hotfix branch
git branch -d hotfix/critical-bug
```

**Policy:** Hotfixes always result in a PATCH version bump.

### Release Branches (Not Used)

This project does **NOT** use long-lived release branches (e.g., `release/1.x`).

**Rationale:**
- Adds complexity without clear benefit for CLI tool
- Creates merge burden between branches
- Version tags serve the same purpose
- Simplifies maintenance

**Exception:** Consider release branches only if:
- Multiple major versions require parallel maintenance
- Enterprise customers require LTS (Long Term Support) versions

---

## GitLab CI/CD Compatibility

### Supported GitLab Versions

`gitlab_ci_cli` supports multiple GitLab versions through the git submodule mechanism.

**Current Support Matrix:**

| gitlab_ci_cli Version | GitLab Version | Status |
|-----------------------|----------------|--------|
| 0.1.x | 15.x, 16.x, 17.x | Supported |
| 1.0.x | 16.x, 17.x, 18.x | Planned |

### GitLab Submodule Version Pinning

The GitLab submodule is pinned to specific versions in `.gitmodules`:

```bash
# Check current GitLab version
cd gitlab
git describe --tags

# Example output: v17.5.0-ee
```

### Version Compatibility Policy

#### Backward Compatibility

- **MINOR versions** add support for newer GitLab features
- **PATCH versions** maintain existing GitLab support
- **MAJOR versions** may drop support for older GitLab versions

#### Forward Compatibility

`gitlab_ci_cli` aims to support GitLab features conservatively:

- Validate syntax that works across supported versions
- Warn about version-specific features
- Document minimum GitLab version for specific features

### Breaking Changes in GitLab

When GitLab introduces breaking changes:

1. **Assess Impact:** Determine if change affects validation logic
2. **Version Decision:**
   - If breaking for users → MAJOR version bump
   - If new feature support → MINOR version bump
   - If internal only → PATCH version bump
3. **Update Documentation:** Document compatibility in upgrade guide

**Example Scenarios:**

**Scenario 1: GitLab removes `only/except` syntax**
- Impact: MAJOR breaking change
- Action: Bump `gitlab_ci_cli` to next MAJOR version
- Document: Add upgrade notes, provide migration guide

**Scenario 2: GitLab adds new `workflow:rules` keyword**
- Impact: New feature, backward compatible
- Action: Bump MINOR version to add support
- Document: Note feature requires GitLab 16.0+

**Scenario 3: GitLab internal refactoring**
- Impact: No user-facing changes
- Action: PATCH version if submodule update needed
- Document: No user documentation needed

### GitLab Submodule Update Strategy

Update the GitLab submodule carefully:

```bash
# 1. Check current submodule version
cd gitlab
git describe --tags

# 2. Fetch latest tags
git fetch origin --tags

# 3. List available versions
git tag -l 'v17.*'

# 4. Checkout desired version
git checkout v17.5.1-ee

# 5. Return to project root
cd ..

# 6. Commit submodule update
git add gitlab
git commit -m "chore: Update GitLab submodule to v17.5.1-ee"

# 7. Run tests to verify compatibility
bundle exec rspec

# 8. Update documentation if needed
# Edit docs/upgrade_guide.md
```

**Testing Requirements:**
- All existing tests must pass
- Test against real-world `.gitlab-ci.yml` files
- Verify no new validation false positives
- Check performance impact

---

## Version Bump Guidelines

### Decision Matrix

| Change Type | Version Bump | Examples |
|-------------|--------------|----------|
| Breaking API change | MAJOR | Remove CLI option, change output format |
| New feature | MINOR | Add command, add validation rule |
| Bug fix | PATCH | Fix incorrect validation logic |
| Documentation | PATCH* | README updates, typo fixes |
| Internal refactor | PATCH* | Code cleanup, no behavior change |
| Security fix | PATCH | Fix vulnerability |
| Performance improvement | MINOR or PATCH** | Depends on impact |

\* Only bump version if releasing. Documentation-only commits don't require releases.

\*\* MINOR if significant user-visible improvement, PATCH if optimization.

### Pre-1.0.0 Exceptions

During the `0.x` pre-release phase:

- Breaking changes allowed in MINOR versions (0.1.0 → 0.2.0)
- More aggressive iteration permitted
- API stability not guaranteed

**Policy:** Once `1.0.0` is released, strict semantic versioning applies.

### Version Bump Checklist

Before bumping version:

1. **Review Changes:**
   - List all commits since last release
   - Categorize as MAJOR/MINOR/PATCH

2. **Update `lib/version.rb`:**
   ```ruby
   VERSION = '1.2.3'  # Old version
   VERSION = '1.3.0'  # New version
   ```

3. **Update `CHANGELOG.md`:**
   - Move `[Unreleased]` changes to new version section
   - Add release date
   - Add comparison link

4. **Update Documentation (if needed):**
   - `README.md` - If features changed
   - `docs/upgrade_guide.md` - If breaking changes
   - `docs/api_reference.md` - If CLI changed

5. **Commit Version Bump:**
   ```bash
   git add lib/version.rb CHANGELOG.md
   git commit -m "chore: Bump version to v1.3.0"
   ```

6. **Create Tag:**
   ```bash
   git tag -a v1.3.0 -m "Release v1.3.0: Add include file processing"
   ```

7. **Push:**
   ```bash
   git push origin master v1.3.0
   ```

---

## Release Process

### Standard Release Workflow

Follow this process for each release:

#### 1. Prepare Release

```bash
# Ensure working directory is clean
git status

# Pull latest changes
git checkout master
git pull origin master

# Run full test suite
bundle exec rspec

# Verify all tests pass before proceeding
```

#### 2. Update Version Files

```bash
# Edit lib/version.rb
# Change VERSION constant to new version

# Edit CHANGELOG.md
# Move [Unreleased] items to new version section
# Add release date
# Add version comparison link
```

Example `CHANGELOG.md` update:

```markdown
## [Unreleased]

### Added
- (empty)

## [1.3.0] - 2025-10-15

### Added
- Include file processing support
- Variable expansion in included files

### Fixed
- Circular dependency detection edge case

[Unreleased]: https://github.com/your-org/gitlab_ci_cli/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/your-org/gitlab_ci_cli/compare/v1.2.3...v1.3.0
```

#### 3. Commit Version Bump

```bash
git add lib/version.rb CHANGELOG.md
git commit -m "chore: Bump version to v1.3.0"
```

#### 4. Create Annotated Tag

```bash
git tag -a v1.3.0 -m "Release v1.3.0: Add include file processing"

# Or with GPG signing
git tag -s v1.3.0 -m "Release v1.3.0: Add include file processing"
```

#### 5. Push Changes

```bash
# Push commit and tag together
git push origin master
git push origin v1.3.0

# Alternative: Push with follow-tags
git push --follow-tags
```

#### 6. Verify Release

```bash
# Verify tag exists remotely
git ls-remote --tags origin

# Verify version.rb content
cat lib/version.rb

# Test installation from tag
git clone --branch v1.3.0 <repository-url> test-install
cd test-install
nix-shell
./bin/gitlab_ci_cli --version
```

#### 7. Create Release Notes (Optional)

If using GitHub/GitLab releases:

1. Navigate to repository releases page
2. Create new release from tag `v1.3.0`
3. Add release title: `v1.3.0 - Add include file processing`
4. Copy relevant sections from `CHANGELOG.md`
5. Publish release

---

## Automation Considerations

### Future Enhancements

Consider automating version management with tools:

- **Version bumping:** Scripts to update `lib/version.rb` automatically
- **Changelog generation:** Generate from commit messages
- **Tag creation:** Automated tagging on merge to master
- **Release notes:** Auto-generate from changelog

**Policy:** Manual process preferred initially to ensure accuracy. Automation can be added once workflow stabilizes.

### Commit Message Conventions

Adopt conventional commits for easier automation:

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature (MINOR)
- `fix`: Bug fix (PATCH)
- `docs`: Documentation only (no version bump)
- `refactor`: Code refactoring (PATCH)
- `test`: Test changes (no version bump)
- `chore`: Maintenance tasks (PATCH or no bump)
- `BREAKING CHANGE`: Breaking change (MAJOR)

**Examples:**

```
feat(cli): Add include file processing support

fix(validation): Correct circular dependency detection

BREAKING CHANGE: Remove deprecated --gitlab-dir option
```

This convention enables:
- Automatic version bump detection
- Automatic changelog generation
- Clear commit history

---

## Summary

### Quick Reference

| Situation | Action | Example |
|-----------|--------|---------|
| Breaking change | Bump MAJOR | 1.2.3 → 2.0.0 |
| New feature | Bump MINOR | 1.2.3 → 1.3.0 |
| Bug fix | Bump PATCH | 1.2.3 → 1.2.4 |
| Documentation only | No bump | - |
| Tag format | `vMAJOR.MINOR.PATCH` | `v1.2.3` |
| Tag type | Annotated | `git tag -a` |
| Branch strategy | Trunk-based | Develop on master |
| Release method | Tag on master | No release branches |

### Version File Checklist

- [ ] `lib/version.rb` - Update VERSION constant
- [ ] `CHANGELOG.md` - Add release section with date
- [ ] Documentation - Update if behavior changed
- [ ] Git tag - Create annotated tag
- [ ] Tests - All tests passing

### Principles

Following MPED architectural principles:

1. **Single Source of Truth:** `lib/version.rb` is authoritative
2. **Reproducibility:** Git tags enable exact version checkout
3. **Fail Fast:** Breaking changes get MAJOR version bump
4. **Minimize State:** No long-lived release branches
5. **Documentation Near Code:** CHANGELOG in repository root

---

## References

- [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)
- [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Trunk Based Development](https://trunkbaseddevelopment.com/)
- [Git Tagging Documentation](https://git-scm.com/book/en/v2/Git-Basics-Tagging)
