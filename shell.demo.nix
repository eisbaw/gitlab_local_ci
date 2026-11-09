{ pkgs ? import <nixpkgs> {} }:

let
  # Import our gitlab_ci_cli package
  gitlab_ci_cli = pkgs.callPackage ./default.nix {};

  # Create a script to test all example projects
  testAllProjects = pkgs.writeShellScriptBin "test-all-projects" ''
    #!/usr/bin/env bash
    set -e

    echo "======================================================================"
    echo "GitLab CI CLI - Demo Test Suite"
    echo "======================================================================"
    echo ""
    echo "Testing gitlab_ci_cli v0.1.0 across 20 example projects"
    echo ""

    PROJECTS_DIR="test_ci_projects"
    PASS_COUNT=0
    FAIL_COUNT=0
    TOTAL=20

    # Test each project
    for i in {1..20}; do
      PROJECT="proj$i"
      CONFIG="$PROJECTS_DIR/$PROJECT/.gitlab-ci.yml"

      if [ ! -f "$CONFIG" ]; then
        echo "⚠️  $PROJECT: Config not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
      fi

      echo -n "Testing $PROJECT... "

      if gitlab_ci_cli lint --entry "$CONFIG" --format text > /dev/null 2>&1; then
        echo "✓ PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        echo "✗ FAIL"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    done

    echo ""
    echo "======================================================================"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed out of $TOTAL projects"
    echo "======================================================================"
    echo ""

    if [ $FAIL_COUNT -eq 0 ]; then
      echo "✓ All projects passed validation!"
      exit 0
    else
      echo "✗ Some projects failed validation"
      exit 1
    fi
  '';

  # Create a script to show detailed info for each project
  showProjectInfo = pkgs.writeShellScriptBin "show-project-info" ''
    #!/usr/bin/env bash

    if [ -z "$1" ]; then
      echo "Usage: show-project-info <project-number>"
      echo "Example: show-project-info 4"
      exit 1
    fi

    PROJECT="proj$1"
    CONFIG="test_ci_projects/$PROJECT/.gitlab-ci.yml"

    if [ ! -f "$CONFIG" ]; then
      echo "Error: Project $PROJECT not found"
      exit 1
    fi

    echo "======================================================================"
    echo "Project: $PROJECT"
    echo "======================================================================"
    echo ""

    echo "--- Validation Result ---"
    gitlab_ci_cli lint --entry "$CONFIG" --format text
    echo ""

    echo "--- Pipeline Statistics ---"
    gitlab_ci_cli lint --entry "$CONFIG" --format json | ${pkgs.jq}/bin/jq -r '
      "Stages: \(.stages | length)",
      "Jobs: \(.jobs | length)",
      "Valid: \(.valid)"
    '
  '';

  # Create a script to generate DAG visualizations
  generateDags = pkgs.writeShellScriptBin "generate-dags" ''
    #!/usr/bin/env bash

    echo "======================================================================"
    echo "Generating DAG Visualizations"
    echo "======================================================================"
    echo ""

    # Projects with interesting DAG structures
    PROJECTS=(4 11 16 19 20)

    mkdir -p dags

    for i in "''${PROJECTS[@]}"; do
      PROJECT="proj$i"
      CONFIG="test_ci_projects/$PROJECT/.gitlab-ci.yml"
      OUTPUT="dags/dag_$PROJECT.svg"

      if [ ! -f "$CONFIG" ]; then
        echo "⚠️  $PROJECT: Config not found"
        continue
      fi

      echo -n "Generating DAG for $PROJECT... "

      if gitlab_ci_cli dag --entry "$CONFIG" | ${pkgs.graphviz}/bin/dot -Tsvg -o "$OUTPUT" 2>/dev/null; then
        echo "✓ $OUTPUT"
      else
        echo "✗ Failed"
      fi
    done

    echo ""
    echo "DAG visualizations saved to: ./dags/"
  '';

  # Reference outputs are owned by the justfile e2e gate (TASK-1). The
  # goldens are defined against the flake dev shell (ruby, graphviz), so
  # these helpers run the gate there rather than in this demo shell.
  regenerateReferences = pkgs.writeShellScriptBin "regenerate-references" ''
    #!/usr/bin/env bash
    exec nix develop -c just e2e-update
  '';

  compareReferences = pkgs.writeShellScriptBin "compare-references" ''
    #!/usr/bin/env bash
    exec nix develop -c just e2e
  '';

  # Create a comprehensive demo script
  runDemo = pkgs.writeShellScriptBin "run-demo" ''
    #!/usr/bin/env bash

    echo "======================================================================"
    echo "GitLab CI CLI - Interactive Demo"
    echo "======================================================================"
    echo ""
    echo "This demo showcases gitlab_ci_cli v0.1.0 capabilities"
    echo ""

    # 1. Show version
    echo ">>> gitlab_ci_cli --version"
    gitlab_ci_cli --version
    echo ""

    # 2. Test simple project
    echo "======================================================================"
    echo "1. Simple Project (proj1)"
    echo "======================================================================"
    echo ""
    echo ">>> gitlab_ci_cli lint --entry test_ci_projects/proj1/.gitlab-ci.yml"
    gitlab_ci_cli lint --entry test_ci_projects/proj1/.gitlab-ci.yml
    echo ""

    # 3. Test DAG project
    echo "======================================================================"
    echo "2. DAG Dependencies (proj4)"
    echo "======================================================================"
    echo ""
    echo ">>> gitlab_ci_cli lint --entry test_ci_projects/proj4/.gitlab-ci.yml"
    gitlab_ci_cli lint --entry test_ci_projects/proj4/.gitlab-ci.yml
    echo ""

    # 4. Test complex project
    echo "======================================================================"
    echo "3. Complex Project (proj19)"
    echo "======================================================================"
    echo ""
    echo ">>> gitlab_ci_cli lint --entry test_ci_projects/proj19/.gitlab-ci.yml --format json | jq"
    gitlab_ci_cli lint --entry test_ci_projects/proj19/.gitlab-ci.yml --format json | ${pkgs.jq}/bin/jq
    echo ""

    # 5. Summary
    echo "======================================================================"
    echo "Demo Complete!"
    echo "======================================================================"
    echo ""
    echo "Try these commands:"
    echo "  test-all-projects       - Test all 20 example projects"
    echo "  show-project-info N     - Show details for project N"
    echo "  generate-dags           - Create DAG visualizations"
    echo "  gitlab_ci_cli --help    - Show all available options"
    echo ""
  '';

in
pkgs.mkShell {
  name = "gitlab-ci-cli-demo";

  buildInputs = [
    gitlab_ci_cli
    pkgs.graphviz    # For DAG visualization with dot
    pkgs.jq          # For JSON output formatting
    testAllProjects
    showProjectInfo
    generateDags
    runDemo
    regenerateReferences
    compareReferences
  ];

  shellHook = ''
    echo "GitLab CI CLI Demo Environment"
    echo "=============================="
    echo ""
    echo "Tool: gitlab_ci_cli v0.1.0"
    echo "Test Projects: 20 (proj1 - proj20)"
    echo ""
    echo "Available Commands:"
    echo "  run-demo                 - Run interactive demonstration"
    echo "  test-all-projects        - Validate all 20 test projects"
    echo "  show-project-info N      - Show detailed info for project N"
    echo "  generate-dags            - Generate DAG visualizations (SVG)"
    echo "  regenerate-references    - Regenerate output reference files"
    echo "  compare-references       - Compare current vs reference outputs"
    echo "  gitlab_ci_cli            - Run the CLI tool directly"
    echo ""
    echo "Regression Testing:"
    echo "  Reference outputs are stored in proj*.output_reference/"
    echo "  Run 'compare-references' to detect breaking changes"
    echo ""
    echo "Quick Start:"
    echo "  run-demo"
    echo ""
  '';
}
