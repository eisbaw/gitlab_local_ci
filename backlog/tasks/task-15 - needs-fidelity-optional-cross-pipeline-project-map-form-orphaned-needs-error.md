---
id: TASK-15
title: >-
  needs fidelity: optional, cross-pipeline/project, map form, orphaned-needs
  error
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T20:12:00Z'
labels:
  - audit
  - needs
  - correctness
  - good-enough
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-4: the needs cascade now lives in PipelineBuilder.cascade_drop_orphaned_needs (lib/pipeline_builder.rb) and applies to dag, run and export-just as well as dry-run, with reasons in Result#excluded_jobs. Done in efda999: optional: true and {project:}/{pipeline:}/{ref:} needs no longer cascade (PipelineBuilder.required_same_pipeline_needs). Still open here: a missing required need should become a Result#errors entry with upstream wording instead of a cascade (this changes the proj20 dag/dry-run goldens: 15 jobs are cascade-dropped there today); MockPipeline#extract_job_needs still reads need['name']; there are still per-command needs parsers in dag/run/export-just/lint/MockPipeline, so fold them onto PipelineBuilder.needs_job_names.

COMPASS 2026-11-09: on the 'good enough' line (tasks that must land before claiming GitLab parity for common configs).

COMPASS: narrowed - optional/cross-project cascade done in efda999; remaining: MockPipeline#extract_job_needs reads need['name'] (map-form needs dropped), fold per-command needs parsers, orphan-need pipeline error. Also absorb rules[].needs flatten from TASK-39.
<!-- SECTION:NOTES:END -->
