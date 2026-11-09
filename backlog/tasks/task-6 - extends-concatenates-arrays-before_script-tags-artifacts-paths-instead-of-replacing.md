---
id: TASK-6
title: >-
  extends concatenates arrays (before_script, tags, artifacts:paths) instead of
  replacing
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T18:42:00Z'
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
- [x] #1 Child arrays replace parent arrays at every level; hashes deep-merge
- [x] #2 Nesting deeper than 10 is a lint error
- [x] #3 Specs for the repro and multi-level/multi-parent extends order
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Write spec/unit/extends_resolver_spec.rb (repro, multi-level, multi-parent order, depth>10) - red. 2. Replace MERGE_KEYS/ARTIFACTS_MERGE_KEYS concat with shared deep_merge (hash merge, array replace); add MAX_NESTING_LEVELS=10 error. 3. Gates. 4. Commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-1: just e2e diffs CLI output for test_ci_projects against projN.output_reference/. As of TASK-1 no golden visibly encodes the array-concatenation bug (dag does not resolve extends, see TASK-4; lint/dry-run output does not print merged scripts/tags), so expect just e2e to stay green after this fix. Prove the fix with rspec; if any golden does change, run just e2e-update, review git diff test_ci_projects/, and explain each change in the commit message. Never regenerate blindly.

Implemented: ExtendsResolver now mirrors Extendable::Entry#extend!: parents resolved recursively, reduced with ConfigMerge.deep_merge in extends: order (later parent wins), job keys merged last. MERGE_KEYS, ARTIFACTS_MERGE_KEYS, merge_job_config, merge_variables, merge_artifacts, deep_dup and require 'set' removed. Added NestingTooDeepError / MAX_NESTING_LEVELS=10 with upstream semantics: an entry with >10 ancestors may not extend, i.e. 11 levels allowed, 12 rejected; message '<key>: nesting too deep in `extends`' (verbatim). Check order unknown -> too deep -> circular as upstream.
Bite: new spec/unit/extends_resolver_spec.rb on pre-fix lib: 12 examples, 7 failures (repro, nested arrays, multi-level, multi-parent, extend non-hidden job, depth, lint depth). After: 12/0. Full rspec 562 examples, 0 failures, 47 pending (just test exits 2 on SimpleCov, TASK-2). just e2e green with no golden change, as TASK-1 predicted.
CLI: lint on audit_config/28_extends_depth.yml -> exit 1 '.l1: nesting too deep in `extends`' (matches upstream key-order walk). export-just on 01_extends_arrays.yml -> before_script 'echo child' only, tags 'a' once.
Note: the brief said 'deeper than 10 is an error'; upstream allows 11 levels (ancestors.count > 10, yaml_optimization.md 'as many as eleven'). Upstream wins.
Gaps filed as TASK-31: hidden templates never resolved as roots, extends reorders jobs after globals, unknown/circular texts differ.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
extends now replaces arrays at every level and deep-merges hashes using ConfigMerge, multi-parent order matches upstream, 12-level nesting rejected with upstream message (11 allowed, per upstream). Dead concat code removed. New extends_resolver_spec (7/12 red pre-fix). e2e unchanged. Gaps in TASK-31.
<!-- SECTION:FINAL_SUMMARY:END -->
