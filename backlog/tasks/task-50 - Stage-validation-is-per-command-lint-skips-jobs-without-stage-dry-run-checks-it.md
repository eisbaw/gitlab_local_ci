---
id: TASK-50
title: >-
  Stage validation is per-command: lint skips jobs without stage:, dry-run
  checks it
status: To Do
assignee: []
created_date: '2026-11-09T21:05:00Z'
labels:
  - audit
  - config
dependencies: []
priority: low
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-7. lint_command validates only an explicit stage:; MockServer#validate_job_configs (dry-run) now also checks the default stage 'test' against stages:. Upstream: '<job> job: chosen stage <stage> does not exist; available stages are ...' for both. Move the stage check into PipelineBuilder (shared path) with upstream wording so lint/dag/dry-run/run/export-just agree; drop the per-command copies. Interacts with TASK-17 (.pre/.post).
<!-- SECTION:DESCRIPTION:END -->
