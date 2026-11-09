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
lint FILE="test_ci_projects/proj1/.gitlab-ci.yml":
    ./bin/gitlab_ci_cli lint --entry {{FILE}}

# Generate DAG visualization
dag FILE="test_ci_projects/proj1/.gitlab-ci.yml" OUTPUT="pipeline.png":
    ./bin/gitlab_ci_cli dag --entry {{FILE}} | dot -Tpng -o {{OUTPUT}}
    @echo "Generated {{OUTPUT}}"

# Dry run simulation
dry-run FILE="test_ci_projects/proj1/.gitlab-ci.yml":
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

# Snapshots lint/dag/dry-run output (stdout, stderr, exit code) for every
# test_ci_projects/projN into a temp dir and diffs it against
# projN.output_reference/. Non-zero CLI exit codes are recorded data (proj13
# dry-run=1 pins a stuck pipeline, TASK-28); only a diff fails. metadata.txt (tool version) and
# dag.svg (derived from dag.dot, graphviz-version dependent) are not compared.
# Supersedes the old test-all-projects loop, which could not express expected
# failures and stopped at proj10 (then accidentally invalid YAML, TASK-44).
# E2E gate: diff all test_ci_projects against their golden outputs
e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    out="$(mktemp -d)"
    trap 'rm -rf "$out"' EXIT
    ./generate_output_references.sh "$out"
    # Same set of golden dirs on both sides (catches added/removed projects).
    diff -u <(cd test_ci_projects && ls -d *.output_reference) <(cd "$out" && ls -d *.output_reference)
    failed=0
    for generated in "$out"/*.output_reference; do
        name="$(basename "$generated")"
        diff -ru -x metadata.txt -x dag.svg "test_ci_projects/$name" "$generated" || failed=1
    done
    if [ "$failed" -ne 0 ]; then
        echo "e2e: FAILED - CLI output differs from goldens. If intended: just e2e-update, then review git diff test_ci_projects/" >&2
        exit 1
    fi
    echo "e2e: OK - all goldens match"

# Each golden dir is replaced wholesale, so files a change no longer
# produces do not linger and break `just e2e`. Afterwards review
# `git diff test_ci_projects/` and justify every change in the commit message.
# Regenerate test_ci_projects goldens from the current CLI (review the diff!)
e2e-update:
    #!/usr/bin/env bash
    set -euo pipefail
    out="$(mktemp -d)"
    trap 'rm -rf "$out"' EXIT
    ./generate_output_references.sh "$out"
    for generated in "$out"/*.output_reference; do
        golden="test_ci_projects/$(basename "$generated")"
        rm -rf "$golden"
        mv "$generated" "$golden"
    done
    # A golden whose project is gone is reported, not deleted: removing
    # reference data is a decision for the human, and just e2e fails on it.
    for golden in test_ci_projects/*.output_reference; do
        [ -d "${golden%.output_reference}" ] || echo "e2e-update: orphaned golden $golden (project removed?)" >&2
    done
