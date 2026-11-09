---
id: TASK-23
title: 'export-just: generated recipes must behave like GitLab jobs'
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:55:00Z'
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
- [ ] #1 Recipes use a shebang/script body so state persists across lines
- [ ] #2 Variables exported, {{ escaped, multi-line blocks intact
- [ ] #3 Generated justfile for test_ci_projects passes 'just --evaluate'/--dry-run
<!-- AC:END -->
