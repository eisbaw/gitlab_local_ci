---
id: TASK-29
title: Retire shell.demo.nix compare-references in favour of just e2e
status: Done
assignee: []
created_date: '2026-11-09T18:08:00Z'
updated_date: '2026-11-09T18:34:00Z'
labels:
  - testing
  - tooling
dependencies: []
priority: low
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
shell.demo.nix has its own compare-references script (lint.txt only, hard-coded 20 projects, packaged gitlab_ci_cli from default.nix) that duplicates and is weaker than just e2e. Its regenerate-references calls generate_output_references.sh, which since TASK-1 uses ./bin/gitlab_ci_cli from the checkout and needs ruby gems + graphviz in PATH; not verified inside shell.demo.nix. One gate, one generator: drop compare-references (or make it call just e2e) and verify regenerate-references in the demo shell or remove it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No second reference-comparison implementation remains
- [x] #2 Whatever demo-shell entry point remains is verified to run
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Demo-shell compare-references/regenerate-references now exec 'nix develop -c just e2e[-update]'; no second comparator. Added a CLI-starts preflight to generate_output_references.sh after finding e2e-update in a ruby-less shell would overwrite all goldens with exit-127 output. Verified both helpers run from shell.demo.nix (compare exit 0; regenerate no-op).
<!-- SECTION:FINAL_SUMMARY:END -->
