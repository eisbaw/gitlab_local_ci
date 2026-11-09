---
id: TASK-52
title: >-
  Default job stage 'test' is re-derived per command instead of composed into
  the job
status: To Do
assignee: []
created_date: '2026-11-09T21:52:00Z'
labels:
  - audit
  - config
dependencies: []
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-17. compose_jobs leaves stage: unset for a job without one, so dag_command, run_command, export_just_command, MockPipeline and filter_jobs_by_rules each re-apply the default 'test' (PipelineBuilder::DEFAULT_JOB_STAGE / literal 'test'). Upstream Entry::Job carries stage default 'test' in its value (normalized job). Compose stage: into job_definitions once and drop the per-command fallbacks. Watch dag tooltips (golden change) and lint's job dump.
<!-- SECTION:DESCRIPTION:END -->
