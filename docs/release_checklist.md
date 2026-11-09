# Release Checklist

Practical checklist for releasing new versions of gitlab_ci_cli. Copy this checklist and check off items as you complete them.

## Pre-Release Verification

### Code Quality
- [ ] All tests pass: `just test`
- [ ] Integration tests pass: `just test-integration`
- [ ] All test projects match their goldens: `just e2e`
- [ ] No failing or skipped tests (review output carefully)
- [ ] Code coverage meets or exceeds baseline (review RSpec output)
- [ ] No security vulnerabilities in dependencies (if any gems added)

### Documentation
- [ ] README.md reflects current features and usage
- [ ] CHANGELOG.md updated with all changes since last release
  - Follow [Keep a Changelog](https://keepachangelog.com/) format
  - Categorize: Added, Changed, Deprecated, Removed, Fixed, Security
  - Include dates and version links at bottom
- [ ] API reference up to date: `docs/api_reference.md`
- [ ] Architecture docs reflect current design: `docs/architecture.md`
- [ ] All example commands in README verified to work
- [ ] No broken internal links in documentation

### Examples and Test Projects
- [ ] All example commands in README tested manually
- [ ] Test projects reflect documented features
- [ ] No stale or outdated example configurations

## Version Management

### Update Version Number
Decide on version number following [Semantic Versioning](https://semver.org/):
- MAJOR: Incompatible API changes
- MINOR: Backward-compatible functionality additions
- PATCH: Backward-compatible bug fixes

- [ ] Update `VERSION` constant in `lib/version.rb`
- [ ] Update version references in README.md (if any)
- [ ] Update `[Unreleased]` section in CHANGELOG.md to new version with date
  - Format: `## [X.Y.Z] - YYYY-MM-DD`
- [ ] Add new `[Unreleased]` section at top of CHANGELOG.md
- [ ] Update version comparison links at bottom of CHANGELOG.md

### Git Tagging
- [ ] Commit all version updates: `git add -A && git commit -m "Release vX.Y.Z"`
- [ ] Create annotated git tag: `git tag -a vX.Y.Z -m "Release version X.Y.Z"`
- [ ] Verify tag created: `git tag -l`
- [ ] Push commits: `git push origin master`
- [ ] Push tag: `git push origin vX.Y.Z`

## Quality Verification (Post-Tag)

### Fresh Checkout Testing
- [ ] Clone repository to temporary directory
- [ ] Enter nix-shell in fresh checkout
- [ ] Run `just setup` to initialize
- [ ] Run `just test` to verify tests pass
- [ ] Run `./bin/gitlab_ci_cli --version` to verify version number
- [ ] Test core commands: lint, dag, dry-run on sample project
- [ ] Verify no missing files or broken references

### Cross-Platform Testing (if applicable)
- [ ] Test on Linux (primary platform)
- [ ] Test on macOS (if Nix available)
- [ ] Verify nix-shell works correctly on all platforms

### Performance Benchmarking
- [ ] Measure cold start time: `time ./bin/gitlab_ci_cli lint --entry test_ci_projects/proj1/.gitlab-ci.yml`
- [ ] Verify performance meets expectations (target: <0.5s for simple configs)
- [ ] Test with large config (proj20): `time ./bin/gitlab_ci_cli lint --entry test_ci_projects/proj20/.gitlab-ci.yml`
- [ ] Document any performance regressions

## Release Creation

### GitHub Release
- [ ] Navigate to GitHub repository releases page
- [ ] Click "Draft a new release"
- [ ] Select tag: `vX.Y.Z`
- [ ] Release title: `Version X.Y.Z`
- [ ] Copy relevant CHANGELOG.md section into release notes
- [ ] Add highlights or notable changes at top
- [ ] Mark as pre-release if applicable (beta, alpha, RC)
- [ ] Publish release

### Release Artifacts (if applicable)
- [ ] No distribution artifacts currently (Git-based distribution only)
- [ ] Future: Consider creating standalone binaries if needed

## Post-Release Tasks

### Verification
- [ ] Verify release appears on GitHub releases page
- [ ] Verify tag visible: `git ls-remote --tags origin`
- [ ] Test cloning from GitHub and following installation instructions
- [ ] Confirm version number correct in fresh clone: `./bin/gitlab_ci_cli --version`

### Communication
- [ ] Update project status in README if needed
- [ ] Announce release (if applicable):
  - Internal team notification
  - Project mailing list
  - Social media
  - Relevant forums or communities
- [ ] Close associated GitHub milestone (if used)
- [ ] Close related GitHub issues with "Fixed in vX.Y.Z" comment

### Cleanup
- [ ] Archive old branches if applicable
- [ ] Review and close stale issues/PRs
- [ ] Update project board or tracking system

## Rollback Procedure (If Issues Found)

If critical issues discovered after release:

1. **Assess severity**:
   - Minor issue: Fix in patch release
   - Critical bug: Consider rollback

2. **Rollback steps** (critical issues only):
   - [ ] Delete GitHub release (mark as draft, don't delete permanently)
   - [ ] DO NOT delete git tag (breaks existing checkouts)
   - [ ] Create hotfix branch from previous stable tag
   - [ ] Fix issue and create new patch release
   - [ ] Document issue in CHANGELOG.md "Fixed" section

3. **Communication**:
   - [ ] Notify users of issue immediately
   - [ ] Provide workaround if available
   - [ ] Announce hotfix release timeline

## Release Validation Checklist Summary

Quick verification that all critical paths work:

```bash
# Clone and test
git clone <repo-url> /tmp/gitlab_ci_cli-test
cd /tmp/gitlab_ci_cli-test
nix-shell
just setup
just test

# Verify commands
./bin/gitlab_ci_cli --version
./bin/gitlab_ci_cli lint --entry test_ci_projects/proj1/.gitlab-ci.yml
./bin/gitlab_ci_cli dag --entry test_ci_projects/proj4/.gitlab-ci.yml | dot -Tpng -o /tmp/test.png
./bin/gitlab_ci_cli dry-run --entry test_ci_projects/proj4/.gitlab-ci.yml

# Cleanup
cd /tmp && rm -rf gitlab_ci_cli-test test.png
```

## Notes on Release Process

### Version Numbering Philosophy
- Start at 0.1.0 for initial working version
- Stay in 0.x.y until API stabilizes
- Move to 1.0.0 when ready for production use and API is stable
- Patch releases (0.1.1, 0.1.2) for bug fixes only
- Minor releases (0.2.0, 0.3.0) for new features

### CHANGELOG.md Best Practices
- Write for users, not developers
- Focus on "what changed" from user perspective
- Include migration instructions for breaking changes
- Link to relevant issues/PRs where helpful
- Keep "Unreleased" section for ongoing work

### Git Tag Strategy
- Always use annotated tags: `git tag -a vX.Y.Z -m "message"`
- Never delete published tags (breaks reproducibility)
- Tag format: `vX.Y.Z` (lowercase v prefix)
- Tag message should be concise: "Release version X.Y.Z"

### Testing Before Release
- Test in clean environment (not your development directory)
- Verify nix-shell works from scratch
- Test with minimum required dependencies
- Verify examples in README actually work

### What NOT to Include in Releases
- Development documentation (arch.md, implementation notes)
- Debug builds or intermediate artifacts
- Sensitive information (API keys, tokens)
- Large binary files (use Git LFS or external hosting)

### Emergency Hotfix Process
If critical bug found after release:
1. Create hotfix branch from release tag
2. Fix bug with minimal changes
3. Update CHANGELOG.md with patch version
4. Follow abbreviated release process (skip non-critical checks)
5. Release as patch version (X.Y.Z+1)
6. Merge hotfix back to main branch

## Common Pitfalls to Avoid

- [ ] Forgetting to update CHANGELOG.md before tagging
- [ ] Not testing in clean environment (works on dev machine only)
- [ ] Tagging before committing version number changes
- [ ] Pushing commits without pushing tag
- [ ] Not verifying version number in released code
- [ ] Breaking changes in patch releases
- [ ] Incomplete or missing release notes
- [ ] Not testing examples in documentation
- [ ] Forgetting to close milestone/issues

## Automation Opportunities

Current process is manual. Future improvements:
- Automated version bumping script
- Pre-release validation script
- Automated CHANGELOG.md generation from commits
- CI/CD pipeline for release builds
- Automated GitHub release creation

Note: Prefer manual process initially to ensure quality and understanding. Automate only after process is proven and stable.
