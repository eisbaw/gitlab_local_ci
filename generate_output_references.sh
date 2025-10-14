#!/usr/bin/env bash
set -e

echo "======================================================================"
echo "Generating Output References for Test Projects"
echo "======================================================================"
echo ""

PROJECTS_DIR="test_ci_projects"
TOTAL_PROJECTS=20

# Projects with interesting DAG structures
DAG_PROJECTS=(4 11 16 19 20)

# Check if gitlab_ci_cli is available
if ! command -v gitlab_ci_cli &> /dev/null; then
    echo "Error: gitlab_ci_cli not found in PATH"
    echo "Please run this script from nix-shell shell.demo.nix"
    exit 1
fi

# Check if we're in the right directory
if [ ! -d "$PROJECTS_DIR" ]; then
    echo "Error: $PROJECTS_DIR directory not found"
    echo "Please run this script from the project root"
    exit 1
fi

# Function to generate reference outputs for a project
generate_reference() {
    local proj_num=$1
    local proj_name="proj${proj_num}"
    local proj_dir="${PROJECTS_DIR}/${proj_name}"
    local output_dir="${PROJECTS_DIR}/${proj_name}.output_reference"
    local config="${proj_dir}/.gitlab-ci.yml"

    if [ ! -f "$config" ]; then
        echo "⚠️  ${proj_name}: Config not found"
        return
    fi

    echo -n "Generating references for ${proj_name}... "

    # Create output directory
    mkdir -p "$output_dir"

    # Generate lint outputs in all formats
    # Text format
    set +e  # Don't exit on error
    gitlab_ci_cli lint --entry "$config" --format text > "$output_dir/lint.txt" 2>&1
    echo $? > "$output_dir/lint.exit_code"
    set -e

    # JSON format
    gitlab_ci_cli lint --entry "$config" --format json > "$output_dir/lint.json" 2>&1 || true

    # JUnit format
    gitlab_ci_cli lint --entry "$config" --format junit > "$output_dir/lint.junit.xml" 2>&1 || true

    # Generate DAG output if this is a DAG project
    if [[ " ${DAG_PROJECTS[@]} " =~ " ${proj_num} " ]]; then
        # DOT format
        set +e  # Don't exit on error
        gitlab_ci_cli dag --entry "$config" > "$output_dir/dag.dot" 2>&1
        echo $? > "$output_dir/dag.exit_code"
        set -e

        # PNG visualization (if dot is available)
        if command -v dot &> /dev/null; then
            if [ -s "$output_dir/dag.dot" ]; then
                dot -Tpng "$output_dir/dag.dot" -o "$output_dir/dag.png" 2>/dev/null || true
            fi
        fi
    fi

    # Create a metadata file
    cat > "$output_dir/metadata.txt" <<EOF
Generated: $(date -Iseconds)
Project: ${proj_name}
Config: ${config}
Tool Version: $(gitlab_ci_cli --version)
EOF

    echo "✓"
}

# Generate references for all projects
for i in $(seq 1 $TOTAL_PROJECTS); do
    generate_reference $i
done

echo ""
echo "======================================================================"
echo "Reference Generation Complete"
echo "======================================================================"
echo ""
echo "Generated output references in:"
echo "  ${PROJECTS_DIR}/proj*.output_reference/"
echo ""
echo "Each project has:"
echo "  - lint.txt          (text format output)"
echo "  - lint.json         (JSON format output)"
echo "  - lint.junit.xml    (JUnit XML format output)"
echo "  - lint.exit_code    (command exit code)"
echo "  - metadata.txt      (generation metadata)"
echo ""
echo "Projects with DAG visualizations (4, 11, 16, 19, 20) also have:"
echo "  - dag.dot           (Graphviz DOT format)"
echo "  - dag.png           (PNG visualization)"
echo "  - dag.exit_code     (command exit code)"
echo ""
