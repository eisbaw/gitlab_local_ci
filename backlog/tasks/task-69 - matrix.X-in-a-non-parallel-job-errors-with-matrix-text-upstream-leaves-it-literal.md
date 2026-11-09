---
id: TASK-69
title: >-
  $[[ matrix.X ]] in a non-parallel job errors with matrix text; upstream leaves
  it literal
status: To Do
assignee: []
created_date: '2026-11-09T23:23:00Z'
labels:
  - audit
  - hardening
dependencies: []
priority: low
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From QA: upstream only interpolates when the job has job_variables; with none the need stays literal and fails as an undefined need. Both reject, different text/conditions.
<!-- SECTION:DESCRIPTION:END -->
