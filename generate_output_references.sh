#!/usr/bin/env bash
# Usage: generate_output_references.sh OUT_ROOT
#
# Snapshot CLI output (lint text/json/junit, dag, dry-run; stdout, stderr and
# exit code of each) for every test_ci_projects/projN into
# OUT_ROOT/projN.output_reference/. OUT_ROOT must be an empty directory, so
# a snapshot never inherits stale files from an earlier run.
#
# One generator, two callers (see justfile):
#   just e2e          -> generate into a temp dir, diff against the goldens
#   just e2e-update   -> generate into a temp dir, replace the goldens with it
#
# Uses ./bin/gitlab_ci_cli from this checkout, not a PATH-installed build,
# so the gate tests the working tree. Run from the dev shell (graphviz for
# dag.svg). Must run with the repo root as cwd: outputs embed the relative
# config path, so a different cwd would change every golden.
#
# Exit codes are recorded, not acted on: a non-zero lint exit (proj11, the
# missing .pre stage, TASK-17) is expected data, and the diff decides pass/fail.
set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: $0 OUT_ROOT" >&2; exit 2; }
OUT_ROOT="$(realpath "$1")"
[ -d "$OUT_ROOT" ] && [ -z "$(ls -A "$OUT_ROOT")" ] || { echo "error: OUT_ROOT '$1' must be an existing empty directory" >&2; exit 1; }

cd "$(dirname "${BASH_SOURCE[0]}")"

PROJECTS_DIR="test_ci_projects"
CLI="./bin/gitlab_ci_cli"
GITLAB_DIR="./gitlab"

[ -d "$PROJECTS_DIR" ] || { echo "error: $PROJECTS_DIR not found" >&2; exit 1; }
[ -d "$GITLAB_DIR/lib" ] || { echo "error: $GITLAB_DIR submodule not checked out (git submodule update --init)" >&2; exit 1; }
command -v dot >/dev/null || { echo "error: graphviz 'dot' not on PATH; run inside the dev shell" >&2; exit 1; }
# A CLI that cannot start (e.g. no ruby on PATH) would otherwise be
# recorded as exit 127 everywhere, and e2e-update would overwrite every
# golden with that. Fail before writing anything.
"$CLI" --version >/dev/null 2>&1 || { echo "error: $CLI does not run (is ruby on PATH? run inside the dev shell)" >&2; exit 1; }

STDERR_LINES_MAX=50

# Ambient CI/GitLab variables (set when this runs inside a GitLab job) reach
# the CLI, e.g. CI_DEFAULT_BRANCH in include rules. Unset them so the goldens
# do not depend on where the gate runs.
mapfile -t ambient_ci_vars < <(env | sed -n -E 's/^((CI|GITLAB)_[A-Za-z0-9_]*)=.*/\1/p')
unset_ci_args=()
for var in "${ambient_ci_vars[@]}"; do unset_ci_args+=(-u "$var"); done

# Every command derives CI_COMMIT_* and CI_DEFAULT_BRANCH from the git state
# of this checkout (lib/predefined_variables.rb) for include and job rules,
# and proj8/12/16/20 rules test them, so
# the goldens would differ on a feature branch, a detached HEAD (how GitLab
# CI checks out) or a tagged commit. The goldens describe a push pipeline on
# the default branch 'main', untagged, at a fixed SHA; --variables overlays
# the git-derived values, the same for every command.
pinned_git_context=(
    --variables CI_COMMIT_BRANCH=main
    --variables CI_COMMIT_REF_NAME=main
    --variables CI_COMMIT_REF_SLUG=main
    --variables CI_COMMIT_TAG=
    --variables CI_DEFAULT_BRANCH=main
    --variables CI_COMMIT_SHA=0000000000000000000000000000000000000000
    --variables CI_COMMIT_SHORT_SHA=00000000
)

# Run the CLI: stdout to $1, stderr to $1.stderr (only if non-empty; at most
# STDERR_LINES_MAX lines plus a total line count), exit code to $2.
# Streams are kept apart because stdout is block-buffered into a file while
# stderr is not: merged, a warning's position would depend on the buffer, and
# json/xml/dot payloads would stop being valid documents.
snapshot() {
    local out="$1" code_file="$2"; shift 2
    local err code=0
    err="$(env "${unset_ci_args[@]}" "$CLI" "$@" --gitlab-dir "$GITLAB_DIR" 2>&1 > "$out")" || code=$?
    if [ -n "$err" ]; then
        # Bound on golden size. It was needed for proj13's stuck dry-run
        # (one warning per job per simulated second, ~110k lines) until
        # TASK-28; total_lines keeps any regression to that visible.
        { head -n "$STDERR_LINES_MAX" <<< "$err"; echo "# total_lines=$(wc -l <<< "$err")"; } > "${out}.stderr"
    fi
    echo "$code" > "$code_file"
}

generate_reference() {
    local proj_dir="$1"
    local proj_name config output_dir
    proj_name="$(basename "$proj_dir")"
    config="${proj_dir}/.gitlab-ci.yml"
    output_dir="${OUT_ROOT}/${proj_name}.output_reference"

    [ -f "$config" ] || { echo "error: ${config} missing" >&2; exit 1; }
    mkdir -p "$output_dir"

    local o="$output_dir"
    snapshot "$o/lint.txt"       "$o/lint.exit_code"       lint --entry "$config" --format text "${pinned_git_context[@]}"
    snapshot "$o/lint.json"      "$o/lint.json.exit_code"  lint --entry "$config" --format json "${pinned_git_context[@]}"
    snapshot "$o/lint.junit.xml" "$o/lint.junit.exit_code" lint --entry "$config" --format junit "${pinned_git_context[@]}"
    snapshot "$o/dag.dot"        "$o/dag.exit_code"        dag  --entry "$config" "${pinned_git_context[@]}"
    # Simulated time, so the timeline is deterministic.
    snapshot "$o/dry-run.txt"    "$o/dry-run.exit_code"    dry-run --entry "$config" --runners ./runners "${pinned_git_context[@]}"

    # dag.svg is derived from dag.dot (which is diffed) and its bytes depend on
    # the graphviz version, so the gate ignores it. Kept for human browsing.
    if [ "$(cat "$output_dir/dag.exit_code")" -eq 0 ] && [ -s "$output_dir/dag.dot" ]; then
        dot -Tsvg "$output_dir/dag.dot" -o "$output_dir/dag.svg"
    fi

    # Not diffed: Tool Version would fail the gate on every version bump. No
    # timestamp (git history records when goldens changed), so regenerating
    # does not churn it.
    cat > "$output_dir/metadata.txt" <<EOF
Project: ${proj_name}
Config: ${config}
Tool Version: $("$CLI" --version)
EOF
}

# Version sort so proj2 precedes proj10; the glob excludes *.output_reference.
mapfile -t projects < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -name 'proj*' ! -name '*.output_reference' | sort -V)
[ "${#projects[@]}" -gt 0 ] || { echo "error: no projects under $PROJECTS_DIR" >&2; exit 1; }

for proj_dir in "${projects[@]}"; do
    generate_reference "$proj_dir"
done
echo "snapshotted ${#projects[@]} projects into ${OUT_ROOT}"
