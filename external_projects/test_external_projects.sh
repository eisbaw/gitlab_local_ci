#!/usr/bin/env bash
# Test external projects with lint, dag, and dry-run

set -e

# Get absolute path to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_PATH="$PROJECT_ROOT/bin/gitlab_ci_cli"
RESULTS_DIR="$SCRIPT_DIR/test_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Initialize results
mkdir -p "$RESULTS_DIR"
SUMMARY_FILE="$RESULTS_DIR/summary_$TIMESTAMP.md"

echo "# External Projects Test Results" > "$SUMMARY_FILE"
echo "Generated: $(date)" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Statistics
total_projects=0
lint_passed=0
dag_passed=0
dryrun_passed=0

# Header
echo "Testing external GitLab CI projects..."
echo ""
printf "%-20s %-10s %-10s %-10s\n" "Project" "Lint" "DAG" "Dry-Run"
echo "----------------------------------------------------------------"

# Test each project
for project_dir in */; do
    project=$(basename "$project_dir")
    ci_file="$project_dir/.gitlab-ci.yml"

    # Skip if no .gitlab-ci.yml
    if [ ! -f "$ci_file" ]; then
        continue
    fi

    total_projects=$((total_projects + 1))
    project_results_dir="$RESULTS_DIR/$project"
    mkdir -p "$project_results_dir"

    # Get absolute path to CI file
    ci_file_abs="$SCRIPT_DIR/$ci_file"

    # Test lint
    lint_status="✗"
    if (cd "$PROJECT_ROOT" && nix-shell --run "$CLI_PATH lint --entry $ci_file_abs") > "$project_results_dir/lint.txt" 2>&1; then
        lint_status="✓"
        lint_passed=$((lint_passed + 1))
    fi

    # Test DAG
    dag_status="✗"
    if (cd "$PROJECT_ROOT" && nix-shell --run "$CLI_PATH dag --entry $ci_file_abs") > "$project_results_dir/dag.dot" 2>&1; then
        dag_status="✓"
        dag_passed=$((dag_passed + 1))

        # Generate SVG if dot is available
        if command -v dot &> /dev/null; then
            dot -Tsvg "$project_results_dir/dag.dot" -o "$project_results_dir/dag.svg" 2>/dev/null || true
        fi
    fi

    # Test dry-run
    dryrun_status="✗"
    runners_dir_abs="$SCRIPT_DIR/$project_dir/runners"
    if timeout 60 bash -c "(cd \"$PROJECT_ROOT\" && nix-shell --run \"$CLI_PATH dry-run --entry $ci_file_abs --runners $runners_dir_abs\")" > "$project_results_dir/dry-run.txt" 2>&1; then
        dryrun_status="✓"
        dryrun_passed=$((dryrun_passed + 1))
    fi

    # Print row
    printf "%-20s %-10s %-10s %-10s\n" "$project" "$lint_status" "$dag_status" "$dryrun_status"

    # Add to summary
    echo "## $project" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "- **Lint:** $lint_status" >> "$SUMMARY_FILE"
    echo "- **DAG:** $dag_status" >> "$SUMMARY_FILE"
    echo "- **Dry-Run:** $dryrun_status" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"

    if [ "$lint_status" = "✗" ]; then
        echo "**Lint Error:**" >> "$SUMMARY_FILE"
        echo '```' >> "$SUMMARY_FILE"
        head -20 "$project_results_dir/lint.txt" >> "$SUMMARY_FILE"
        echo '```' >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
    fi
done

echo ""
echo "================================================================"
echo "Summary"
echo "================================================================"
echo ""

# Calculate percentages
lint_pct=$((lint_passed * 100 / total_projects))
dag_pct=$((dag_passed * 100 / total_projects))
dryrun_pct=$((dryrun_passed * 100 / total_projects))

echo "Projects tested: $total_projects"
echo ""
echo "Lint:     $lint_passed/$total_projects passed ($lint_pct%)"
echo "DAG:      $dag_passed/$total_projects passed ($dag_pct%)"
echo "Dry-Run:  $dryrun_passed/$total_projects passed ($dryrun_pct%)"
echo ""

# Add statistics to summary
echo "## Statistics" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "- **Projects tested:** $total_projects" >> "$SUMMARY_FILE"
echo "- **Lint:** $lint_passed/$total_projects passed ($lint_pct%)" >> "$SUMMARY_FILE"
echo "- **DAG:** $dag_passed/$total_projects passed ($dag_pct%)" >> "$SUMMARY_FILE"
echo "- **Dry-Run:** $dryrun_passed/$total_projects passed ($dryrun_pct%)" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

echo "Results saved to: $RESULTS_DIR/"
echo "Summary: $SUMMARY_FILE"

# Exit with failure if not all lints passed
if [ $lint_passed -ne $total_projects ]; then
    exit 1
fi

exit 0
