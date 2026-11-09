---
id: TASK-36
title: 'Define CLI convention for ''no pipeline'' and ''no jobs'': exit code and stream'
status: To Do
assignee: []
created_date: '2026-11-09T19:23:00Z'
updated_date: '2026-11-09T21:52:00Z'
labels:
  - audit
  - cli
dependencies: []
priority: low
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-4 reviews. workflow:rules skip prints PipelineBuilder::WORKFLOW_SKIPPED_MESSAGE everywhere but: dry-run stdout exit 1, dag stderr 'Error:' exit 2, run/export-just stderr 'Error:' exit 1. When rules leave zero jobs, dry-run says 'No jobs defined in configuration' (misleading) exit 1 while dag/export-just print an empty graph/justfile exit 0. Upstream treats neither as a config error. Pick one convention (exit code + stream + text), document it in --help/README, spec it per command.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Same exit code and stream for workflow skip and empty pipeline in dag, dry-run, run, export-just
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-17 (732515b): a pipeline whose kept jobs are all in .pre/.post is now the same data as 'rules left no job' (pipeline_jobs empty, the edge jobs in excluded_jobs with PipelineBuilder::ONLY_EDGE_STAGE_JOBS_MESSAGE, upstream rules_failure_message). Whatever convention this task picks covers it automatically; dry-run currently says 'No jobs defined in configuration' for it, which is wrong in the same way.
<!-- SECTION:NOTES:END -->
