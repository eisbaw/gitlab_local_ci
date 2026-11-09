---
id: TASK-66
title: 'export-just: ''_''-prefixed recipe names are private in just, hidden from --list'
status: To Do
assignee: []
created_date: '2026-11-09T23:22:00Z'
updated_date: '2026-11-09T23:22:00Z'
labels:
  - audit
  - export-just
  - ux
dependencies: []
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
recipe_base maps a job name that does not start with a letter to a name starting with '_' (e.g. '1build' -> _1build by the prefix rule, '[aws] x' -> _aws_x by the run-to-'_' rule), and the collision suffix keeps that base. just treats every recipe whose name starts with '_' as private: 'just _1build' runs it, but it is missing from 'just --list' and 'just --summary' (verified with just 1.51 on a '1build' + 'ok' config: both list only ok), so the job looks absent from the exported justfile. Found while writing the TASK-60 property spec. Options: prefix with a letter instead (e.g. 'job_'), which renames such recipes (an output-format change: upgrade note), or another just mechanism to list them (none known). Decide and spec with a job named '1build' visible in --list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A job whose name starts with a digit or symbol is listed by just --list
- [ ] #2 Upgrade note if names change
<!-- AC:END -->
