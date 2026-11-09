---
id: TASK-26
title: 'dry-run: trigger jobs should not take a runner'
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:55:00Z'
labels:
  - audit
  - dry-run
dependencies:
  - TASK-1
priority: low
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
trigger: jobs are scheduled on a runner; upstream bridges never run on runners.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Bridge jobs complete without a runner and show as triggered
<!-- AC:END -->
