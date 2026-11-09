---
id: TASK-17
title: Add .pre/.post edge stages
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T21:06:00Z'
labels:
  - audit
  - config
dependencies:
  - TASK-1
priority: medium
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
We do not inject .pre/.post: 'stage: .pre' is undefined; user-listed .pre mid-list kept in place. Upstream Config::Stages.wrap_with_edge_stages (replaced EdgeStagesInjector since v17.5) always puts .pre first and .post last. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 .pre/.post usable without declaring, always first/last
- [ ] #2 Pipeline of only .pre/.post jobs handled like upstream
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-7: dry-run now rejects a job whose stage is not in stages: (MockServer#validate_job_configs, lint's wording), so the proj11 dry-run golden is exit 1 "Job 'verify-includes' references undefined stage '.pre'". Once .pre/.post are injected first/last that golden flips back to a simulation with verify-includes in the first wave; MockPipeline orders by Result#stages, so injection in PipelineBuilder is enough.
<!-- SECTION:NOTES:END -->
