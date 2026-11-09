---
id: TASK-71
title: >-
  Allowed failures print 'Error: Job X failed' although exit is 0 and summary
  says allowed
status: To Do
assignee: []
created_date: '2026-11-09T23:23:00Z'
labels:
  - audit
  - hardening
dependencies: []
priority: low
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From QA: run with allow_failure exit_codes prints 'Error: Job allowed failed with exit code 3' then 'allowed to fail', exit 0. Print a warning-level line instead.
<!-- SECTION:DESCRIPTION:END -->
