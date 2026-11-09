---
id: TASK-49
title: 'dry-run simulates when: manual / delayed jobs as if they ran'
status: To Do
assignee: []
created_date: '2026-11-09T21:05:00Z'
labels:
  - audit
  - dry-run
dependencies: []
priority: medium
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-7. MockPipeline#runnable_after? treats manual and delayed like on_success, so the simulator starts them. Upstream: a manual job becomes 'manual' (blocked until a human plays it; with allow_failure: true by default it is ignored in composites), delayed waits start_in. Decide what the dry-run timeline should show (e.g. 'manual, not started' and continue), then make later stages/needs follow upstream Composite rules for :manual (IGNORED_STATUSES with allow_failure; blocking when allow_failure: false). proj4/8/12/13/17/18/20 have manual jobs.
<!-- SECTION:DESCRIPTION:END -->
