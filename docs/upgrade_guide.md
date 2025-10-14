# Upgrade Guide

This document provides guidance for upgrading gitlab_ci_cli and maintaining compatibility with different GitLab versions.

## Table of Contents

- [Version Compatibility](#version-compatibility)
- [Upgrading gitlab_ci_cli](#upgrading-gitlab_ci_cli)
- [GitLab CI/CD Version Support](#gitlab-cicd-version-support)
- [Breaking Changes](#breaking-changes)
- [Migration Guide](#migration-guide)
- [Troubleshooting](#troubleshooting)

---

## Version Compatibility

### gitlab_ci_cli Versions

Current version: **0.1.0**

#### Version History

- **0.1.0** (Current) - Initial standalone release
  - Zero external gem dependencies
  - Pure Ruby + YAML parsing
  - Support for GitLab CI/CD v15.0 - v17.0 syntax
  - Complete command suite (lint, dag, dry-run)

### Supported GitLab CI/CD Versions

gitlab_ci_cli is tested against and supports GitLab CI/CD configuration syntax from:

| GitLab Version | Support Status | Notes |
|----------------|---------------|-------|
| 17.x | ✅ Full Support | Latest features supported |
| 16.x | ✅ Full Support | All major features supported |
| 15.x | ✅ Full Support | Baseline compatibility |
| 14.x | ⚠️ Partial | Most features work, some newer syntax may not be recognized |
| 13.x | ❌ Not Tested | May work but not officially supported |

### Platform Compatibility

| Platform | Support Status | Notes |
|----------|---------------|-------|
| Linux | ✅ Full Support | Primary development platform |
| macOS | ✅ Full Support | Tested on macOS 11+ |
| Windows (WSL) | ✅ Full Support | Via Windows Subsystem for Linux |
| Windows (native) | ⚠️ Partial | May require path adjustments |

---

## Upgrading gitlab_ci_cli

### From Development Version to 0.1.0

If you've been using a development version, upgrade to 0.1.0:

```bash
cd gitlab_ci_cli
git pull origin master
nix-shell
```

No additional steps required - the tool has no gem dependencies to update.

### Checking Your Version

```bash
./bin/gitlab_ci_cli --version
```

### Upgrade Checklist

Before upgrading:

1. ✅ Review CHANGELOG.md for breaking changes
2. ✅ Backup any custom runner configurations
3. ✅ Test with your existing `.gitlab-ci.yml` files
4. ✅ Run test suite to verify compatibility

After upgrading:

1. ✅ Run `./bin/gitlab_ci_cli lint` on your configs
2. ✅ Verify DAG generation still works
3. ✅ Test dry-run simulations
4. ✅ Check runner configurations load correctly

---

## GitLab CI/CD Version Support

### Supported GitLab CI Features

#### Core Features (All Versions)

- ✅ `stages` definition
- ✅ Job `script` execution
- ✅ `before_script` and `after_script`
- ✅ Job `tags` for runner selection
- ✅ `dependencies` between jobs
- ✅ `needs` for DAG pipelines
- ✅ `extends` for job templates
- ✅ `variables` at job and global level
- ✅ `image` and `services` definitions
- ✅ `artifacts` configuration
- ✅ Multiple stages and parallel jobs

#### Advanced Features

- ✅ `include` directives (local, remote, template)
- ✅ Child pipelines via `trigger`
- ⚠️ `rules` - basic syntax only
- ⚠️ CI/CD templates - limited support
- ❌ GitLab-specific integrations
- ❌ Auto DevOps features

### GitLab Version-Specific Notes

#### GitLab 17.x

**New Features Supported:**
- Enhanced needs syntax
- Improved artifact handling
- Extended variable capabilities

**Known Limitations:**
- Advanced rules expressions not fully validated
- Some new keywords may not be recognized

**Recommendation:** Fully supported, use with confidence

#### GitLab 16.x

**New Features Supported:**
- Component includes (partial support)
- Pipeline efficiency features
- Enhanced job timeout configuration

**Known Limitations:**
- Component catalog integration not implemented
- Some advanced security features not validated

**Recommendation:** Fully supported for standard CI/CD

#### GitLab 15.x

**Baseline Support:**
- All core CI/CD features
- Standard DAG pipelines
- Include directives
- Child pipelines

**Recommendation:** Baseline compatibility target

---

## Breaking Changes

### Version 0.1.0 (Current)

No breaking changes - this is the initial release.

### Future Breaking Changes Policy

Breaking changes will be:
- Documented in CHANGELOG.md
- Announced in release notes
- Accompanied by migration guidance
- Avoided when possible

---

## Migration Guide

### Migrating from Other CI Tools

#### From CircleCI

CircleCI uses `.circleci/config.yml` while GitLab uses `.gitlab-ci.yml`.

**Key Differences:**

| CircleCI | GitLab CI |
|----------|-----------|
| `workflows` | `stages` |
| `jobs` | `jobs` (but different syntax) |
| `steps` | `script` |
| `executors` | `image` + runner tags |

**Migration Steps:**

1. Review your CircleCI configuration
2. Map workflows to GitLab stages
3. Convert job definitions to GitLab format
4. Test with `gitlab_ci_cli lint`

#### From Jenkins

Jenkins uses Groovy-based Jenkinsfiles while GitLab uses YAML.

**Key Differences:**

| Jenkins | GitLab CI |
|---------|-----------|
| `stage` blocks | `stages` definition |
| `steps` | `script` |
| `agent` | runner `tags` |
| `when` conditions | `rules` or `only/except` |

**Migration Steps:**

1. Extract stage names from Jenkinsfile
2. Convert each stage to a GitLab job
3. Map pipeline triggers to GitLab rules
4. Validate with lint command

#### From GitHub Actions

GitHub Actions uses workflow YAML similar to GitLab.

**Key Differences:**

| GitHub Actions | GitLab CI |
|----------------|-----------|
| `on` | `rules` / `only` / `except` |
| `jobs` | `jobs` (similar syntax) |
| `steps` | `script` |
| `runs-on` | runner `tags` |
| `needs` | `needs` (similar) |

**Migration Steps:**

1. Rename workflow file to `.gitlab-ci.yml`
2. Convert `on` triggers to GitLab rules
3. Adjust job syntax (minimal changes needed)
4. Test with `gitlab_ci_cli dry-run`

### Updating Existing Configurations

#### Adding New Features

**Adding needs dependencies:**

Before:
```yaml
test:
  stage: test
  script: npm test
```

After:
```yaml
build:
  stage: build
  script: npm run build

test:
  stage: test
  needs: [build]  # Add dependency
  script: npm test
```

Validate:
```bash
./bin/gitlab_ci_cli lint
./bin/gitlab_ci_cli dag | dot -Tpng -o pipeline.png
```

**Adding include directives:**

Before:
```yaml
stages:
  - build
  - test

build-job:
  stage: build
  script: make build
```

After:
```yaml
include:
  - local: 'shared/ci.yml'

build-job:
  extends: .build-template
```

Validate:
```bash
./bin/gitlab_ci_cli lint --entry .gitlab-ci.yml
```

---

## Troubleshooting

### Common Upgrade Issues

#### Issue: "YAML syntax error after upgrade"

**Cause:** New GitLab versions may have stricter YAML requirements

**Solution:**
```bash
# Validate your YAML
./bin/gitlab_ci_cli lint --verbose

# Check for common issues:
# - Incorrect indentation
# - Missing quotes around special characters
# - Invalid key-value pairs
```

#### Issue: "Circular dependency detected"

**Cause:** Complex needs relationships may create cycles

**Solution:**
```bash
# Visualize dependencies
./bin/gitlab_ci_cli dag | dot -Tpng -o pipeline.png
open pipeline.png

# Look for cycles in the graph
# Remove or reorder needs to break the cycle
```

#### Issue: "Job references undefined stage"

**Cause:** Missing stage in stages list

**Solution:**
```yaml
# Add all stages used by jobs
stages:
  - build
  - test
  - deploy  # Add any missing stages
```

#### Issue: "Runner not found for job"

**Cause:** No runner with matching tags

**Solution:**
```bash
# Check runner configurations
ls -la runners/

# Verify runner tags match job requirements
./bin/gitlab_ci_cli dry-run --verbose
```

#### Issue: "Performance degradation after upgrade"

**Cause:** Large configuration or many includes

**Solution:**
```bash
# Profile the tool
time ./bin/gitlab_ci_cli lint

# Run benchmarks
bundle exec rspec spec/benchmarks/

# Check for:
# - Excessive includes
# - Very large YAML files
# - Deep include nesting
```

### Rollback Procedure

If upgrade causes issues:

```bash
# Check git history
git log --oneline

# Rollback to previous version
git checkout <previous-commit>

# Verify rollback works
./bin/gitlab_ci_cli --version
./bin/gitlab_ci_cli lint
```

### Getting Help

If you encounter upgrade issues:

1. Check [CHANGELOG.md](../CHANGELOG.md) for known issues
2. Review [architecture.md](architecture.md) for design changes
3. Search [GitHub Issues](https://github.com/user/gitlab_ci_cli/issues)
4. Open a new issue with:
   - Your gitlab_ci_cli version
   - Your GitLab CI/CD version
   - Minimal reproduction case
   - Error messages and logs

---

## Best Practices

### Configuration Maintenance

1. **Version Control**
   - Keep `.gitlab-ci.yml` in version control
   - Use branches for testing changes
   - Review diffs before merging

2. **Testing**
   - Always lint before committing
   - Generate DAG to visualize changes
   - Run dry-run to verify execution
   - Use test projects for validation

3. **Documentation**
   - Comment complex job configurations
   - Document custom variables
   - Keep runner configurations up to date
   - Maintain pipeline documentation

4. **Validation Workflow**
   ```bash
   # Pre-commit hook
   #!/bin/bash
   ./bin/gitlab_ci_cli lint || exit 1
   ./bin/gitlab_ci_cli dag > /dev/null || exit 1
   ```

### Staying Up to Date

1. **Monitor GitLab Releases**
   - Subscribe to [GitLab release notes](https://about.gitlab.com/releases/)
   - Review CI/CD feature changes
   - Test new syntax with gitlab_ci_cli

2. **Update Regularly**
   - Pull latest gitlab_ci_cli changes
   - Run full test suite
   - Update documentation
   - Communicate changes to team

3. **Deprecation Handling**
   - Watch for deprecation warnings
   - Plan migration timeline
   - Test with newer syntax
   - Update configurations proactively

---

## Compatibility Matrix

### Feature Support by GitLab Version

| Feature | v15.x | v16.x | v17.x | Notes |
|---------|-------|-------|-------|-------|
| Basic jobs | ✅ | ✅ | ✅ | Full support |
| needs (DAG) | ✅ | ✅ | ✅ | Full support |
| extends | ✅ | ✅ | ✅ | Full support |
| include:local | ✅ | ✅ | ✅ | Full support |
| include:remote | ✅ | ✅ | ✅ | Full support |
| include:template | ⚠️ | ✅ | ✅ | Limited in v15 |
| include:component | ❌ | ⚠️ | ⚠️ | Partial support |
| trigger (child) | ✅ | ✅ | ✅ | Full support |
| rules | ⚠️ | ⚠️ | ⚠️ | Basic validation only |
| workflow:rules | ❌ | ⚠️ | ⚠️ | Not fully validated |
| artifacts | ✅ | ✅ | ✅ | Configuration validated |
| cache | ✅ | ✅ | ✅ | Configuration validated |
| services | ✅ | ✅ | ✅ | Configuration validated |

Legend:
- ✅ Full support and testing
- ⚠️ Partial support, may have limitations
- ❌ Not supported or not tested

---

## Future Roadmap

### Planned Enhancements

**Version 1.1 (Planned)**
- Enhanced rules validation
- Component include support
- Better variable expansion
- Performance improvements

**Version 1.2 (Planned)**
- GitLab 18.x support
- Advanced artifact handling
- Cache simulation
- Enhanced error messages

**Version 2.0 (Future)**
- Plugin system
- Custom validators
- Extended API
- Web interface

---

## References

- [GitLab CI/CD YAML Syntax](https://docs.gitlab.com/ee/ci/yaml/)
- [GitLab Release Notes](https://about.gitlab.com/releases/)
- [Architecture Documentation](architecture.md)
- [API Reference](api_reference.md)
- [CHANGELOG](../CHANGELOG.md)
