---
id: TASK-18
title: >-
  Expand parallel: N and parallel:matrix (incl. needs:parallel:matrix, $[[
  matrix.X ]])
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T20:12:00Z'
labels:
  - audit
  - config
  - feature
  - good-enough
dependencies:
  - TASK-1
priority: medium
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Not expanded at all: matrix jobs keep original name and vanish from dry-run. Upstream Config::Normalizer creates 'job 1/2' and 'job: [aws, x]' names, injects matrix vars, rewrites needs/dependencies; needs:parallel:matrix selects instances; MatrixInterpolator ($[[ matrix.X ]] in needs) is new since v17.5. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Job names and variables match upstream Normalizer for parallel N and matrix
- [ ] #2 needs/dependencies on a parallel job fan out; needs:parallel:matrix selects
- [ ] #3 dag, dry-run, run, export-just all show expanded jobs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COMPASS 2026-11-09: on the 'good enough' line (tasks that must land before claiming GitLab parity for common configs).
<!-- SECTION:NOTES:END -->
