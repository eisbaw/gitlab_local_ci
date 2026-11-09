---
id: TASK-18
title: >-
  Expand parallel: N and parallel:matrix (incl. needs:parallel:matrix, $[[
  matrix.X ]])
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T22:14:00Z'
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
Forward-carried from TASK-10 (7a4b351): CI_NODE_INDEX/CI_NODE_TOTAL were deliberately left out of PredefinedVariables.job_variables because parallel jobs are not expanded yet. When expanding: upstream predefined_variables_from_job_attr sets CI_NODE_TOTAL for every job (Gitlab::Utils::Job.node_total: parallel total, else 1) and CI_NODE_INDEX only for an instance (options[:instance]); add both to job_variables (name: is then the expanded name, e.g. 'rspec 1/3' or 'build: [aws]', and CI_JOB_GROUP_NAME already strips that suffix via PARALLEL_VARIANT_REGEX). Rules of an expanded job see its matrix variables (rules on $PROVIDER, audit_vars/r3 matrix_job).
<!-- SECTION:NOTES:END -->
