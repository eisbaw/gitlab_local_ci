---
id: TASK-6
title: >-
  extends concatenates arrays (before_script, tags, artifacts:paths) instead of
  replacing
status: To Do
assignee: []
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T18:08:00Z'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-1: just e2e diffs CLI output for test_ci_projects against projN.output_reference/. As of TASK-1 no golden visibly encodes the array-concatenation bug (dag does not resolve extends, see TASK-4; lint/dry-run output does not print merged scripts/tags), so expect just e2e to stay green after this fix. Prove the fix with rspec; if any golden does change, run just e2e-update, review git diff test_ci_projects/, and explain each change in the commit message. Never regenerate blindly.
<!-- SECTION:NOTES:END -->
