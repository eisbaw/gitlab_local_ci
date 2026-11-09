---
id: TASK-15
title: >-
  needs fidelity: optional, cross-pipeline/project, map form, orphaned-needs
  error
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:54:00Z'
labels:
  - audit
  - needs
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- needs: [{job: a}] dropped in dry-run: MockPipeline#extract_job_needs reads need['name'].
- needs: {job: x, optional: true} on undefined job: lint rejects, dry-run drops job; upstream skips optional needs.
- needs: [{project: ..}] and [{pipeline: $PARENT_PIPELINE_ID, job: ..}]: lint 'needs undefined job', dry-run deletes job; upstream CrossPipelineDependency (optional key new since v17.5).
- Need on job removed by rules: ours cascade_drop_orphaned_needs silently drops dependent; upstream fails pipeline creation ("'b' job needs 'a' job, but 'a' does not exist in the pipeline") unless optional.
- run --run-deps incl treats needs: [] as no needs (falls back to stage order).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All need forms parse identically in lint, dag, dry-run, run
- [ ] #2 Orphaned non-optional need is a pipeline error with upstream wording
- [ ] #3 Specs per form
<!-- AC:END -->
