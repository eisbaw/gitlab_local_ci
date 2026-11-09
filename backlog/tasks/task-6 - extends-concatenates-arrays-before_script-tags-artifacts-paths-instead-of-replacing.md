---
id: TASK-6
title: >-
  extends concatenates arrays (before_script, tags, artifacts:paths) instead of
  replacing
status: To Do
assignee: []
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T17:54:00Z'
labels:
  - audit
  - config
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ExtendsResolver::MERGE_KEYS / ARTIFACTS_MERGE_KEYS concatenate parent+child arrays: before_script [base, child], tags [a, a]. Upstream Extendable::Entry#extend! uses deep_merge!: hashes merge, child array replaces parent array. Also: extends depth > 10 not rejected (upstream MAX_NESTING_LEVELS = 10).
Repro: .base: {tags: [a], before_script: [echo base]}; t: {extends: .base, tags: [a], before_script: [echo child]} -> ours tags [a,a], before_script [echo base, echo child]; upstream [a], [echo child]. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Child arrays replace parent arrays at every level; hashes deep-merge
- [ ] #2 Nesting deeper than 10 is a lint error
- [ ] #3 Specs for the repro and multi-level/multi-parent extends order
<!-- AC:END -->
