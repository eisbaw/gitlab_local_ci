---
id: TASK-23
title: 'export-just: generated recipes must behave like GitLab jobs'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T22:39:00Z'
labels:
  - audit
  - export-just
  - correctness
dependencies:
  - TASK-1
  - TASK-4
priority: low
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each line runs in its own sh -cu so export/cd don't persist and unset vars abort; YAML vars not exported; '{{' in scripts breaks justfile; --shell option unused; CLI values text-pasted (breaks quoting); multi-line '- |' blocks split per line; escape_script_line is a no-op.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Recipes use a shebang/script body so state persists across lines
- [x] #2 Variables exported, {{ escaped, multi-line blocks intact
- [x] #3 Generated justfile for test_ci_projects passes 'just --evaluate'/--dry-run
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Covered by TASK-51 / 79ef1d8 (one change for both): every description item is fixed - per-line sh -cu replaced by one shebang bash per recipe (state persists; no -u, so unset vars no longer abort); YAML/predefined/CLI variables exported via JobEnvironment (same as run); {{ escaped; --shell removed (was unused); CLI values no longer text-pasted (exported, single-quoted); multi-line '- |' blocks intact; escape_script_line gone. AC#3: all 20 test projects, graph and flat, pass just --list/--evaluate/--dry-run of every recipe.
What is left (by design, documented in the generated header / ExportJustCommand class comment, not bugs): variables are a snapshot at export time (CI_COMMIT_SHA etc.) and cwd is the absolute project dir - regenerate after committing or moving; image/services/cache/artifacts not modelled (same as run); graph recipes model the success path only (when: on_failure jobs are not dependencies, manual jobs run like on_success); just's environment leaks into recipes (TASK-56); no command echo (TASK-57).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Done together with TASK-51 (79ef1d8): shebang recipes from the shared JobEnvironment - one shell per phase, variables exported, {{ escaped, multi-line blocks intact, --shell removed; all 20 test projects pass just --list/--evaluate/--dry-run. Remaining limits are documented design choices (variable snapshot, success-path graph) plus TASK-56/57.
<!-- SECTION:FINAL_SUMMARY:END -->
