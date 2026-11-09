---
id: TASK-29
title: Retire shell.demo.nix compare-references in favour of just e2e
status: To Do
assignee: []
created_date: '2026-11-09T18:08:00Z'
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
- [ ] #1 No second reference-comparison implementation remains
- [ ] #2 Whatever demo-shell entry point remains is verified to run
<!-- AC:END -->
