---
id: TASK-14
title: Honour rule when:/start_in and evaluate only/except
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:54:00Z'
labels:
  - audit
  - rules
  - correctness
dependencies:
  - TASK-1
priority: medium
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- rules: [{when: delayed, start_in: 5 minutes}] crashes dry-run: unknown key start_in.
- Rule when: manual / on_failure computed but unused: such jobs run automatically in dry-run.
- only/except accepted and ignored (upstream Seed::Build#all_of_only?/none_of_except?): only: [tags] job runs on main.
- run stops at first failure ignoring allow_failure (incl. exit_codes) and when: on_failure/always.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 manual jobs not auto-run (shown as manual), on_failure/always semantics in dry-run and run
- [ ] #2 delayed + start_in accepted and simulated
- [ ] #3 only/except refs/variables/changes basic forms evaluated
<!-- AC:END -->
