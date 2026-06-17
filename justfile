# justfile - Common development workflows

# Show all available commands
help:
    @just --list

# Enter nix-shell
shell:
    nix-shell

# Initialize GitLab submodule and install dependencies
setup:
    git submodule update --init
    bundle install

# Run tests
# NOT `bundle exec rspec`: that exports BUNDLE_GEMFILE which propagates via
# Open3 into the CLI subprocess in spec/integration/lint_spec.rb, causing
# double-activation of bundler and "already initialized constant" warnings
# on stderr — which fail the `expect(stderr).to be_empty` assertions.
# `.gems/` is on GEM_PATH via shell.nix shellHook, so plain `rspec` resolves
# the gem set without bundler env-var injection.
test:
    rspec

# Run specific test file
test-file FILE:
    rspec {{FILE}}

# Lint YAML file
lint FILE=".gitlab-ci.yml":
    ./bin/gitlab_ci_cli lint --entry {{FILE}}

# Generate DAG visualization
dag FILE=".gitlab-ci.yml" OUTPUT="pipeline.png":
    ./bin/gitlab_ci_cli dag --entry {{FILE}} | dot -Tpng -o {{OUTPUT}}
    @echo "Generated {{OUTPUT}}"

# Dry run simulation
dry-run FILE=".gitlab-ci.yml":
    ./bin/gitlab_ci_cli dry-run --entry {{FILE}}

# Update GitLab submodule to latest version
update-gitlab:
    cd gitlab && git fetch && git checkout $(git describe --tags --abbrev=0)
    git add gitlab
    @echo "GitLab submodule updated. Review changes before committing."

# Clean temporary files
clean:
    rm -f *.png
    rm -rf tmp/

# Run integration tests
test-integration:
    rspec spec/integration/

# Test CI Projects
# Run all tests for test_ci_projects (lint, dag, dry-run)

# Test project 1 - Minimal config
test-proj1:
    cd test_ci_projects/proj1 && just test

# Test project 2 - Multiple stages
test-proj2:
    cd test_ci_projects/proj2 && just test

# Test project 3 - Parallel jobs
test-proj3:
    cd test_ci_projects/proj3 && just test

# Test project 4 - Needs/DAG
test-proj4:
    cd test_ci_projects/proj4 && just test

# Test project 5 - Variables
test-proj5:
    cd test_ci_projects/proj5 && just test

# Test project 6 - Artifacts
test-proj6:
    cd test_ci_projects/proj6 && just test

# Test project 7 - Services
test-proj7:
    cd test_ci_projects/proj7 && just test

# Test project 8 - Rules/Conditions
test-proj8:
    cd test_ci_projects/proj8 && just test

# Test project 9 - Cache
test-proj9:
    cd test_ci_projects/proj9 && just test

# Test project 10 - Hooks
test-proj10:
    cd test_ci_projects/proj10 && just test

# Test project 11 - Includes
test-proj11:
    cd test_ci_projects/proj11 && just test

# Test project 12 - YAML Anchors
test-proj12:
    cd test_ci_projects/proj12 && just test

# Test project 13 - Extends
test-proj13:
    cd test_ci_projects/proj13 && just test

# Test project 14 - Retry/Timeout
test-proj14:
    cd test_ci_projects/proj14 && just test

# Test project 15 - Reports/Coverage
test-proj15:
    cd test_ci_projects/proj15 && just test

# Test project 16 - Child Pipelines
test-proj16:
    cd test_ci_projects/proj16 && just test

# Test project 17 - Matrix/Parallel
test-proj17:
    cd test_ci_projects/proj17 && just test

# Test project 18 - Resource Groups
test-proj18:
    cd test_ci_projects/proj18 && just test

# Test project 19 - Complex DAG
test-proj19:
    cd test_ci_projects/proj19 && just test

# Test project 20 - Kitchen Sink
test-proj20:
    cd test_ci_projects/proj20 && just test

# Test all projects sequentially
test-all-projects:
    @echo "Testing all 20 CI projects..."
    @for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
        echo ""; \
        echo "=== Testing proj$$i ==="; \
        cd test_ci_projects/proj$$i && just test || exit 1; \
        cd ../..; \
    done
    @echo ""
    @echo "✓ All 20 projects tested successfully!"
