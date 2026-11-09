---
id: TASK-5
title: 'Include merge order reversed: included file overrides main file'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T18:39:00Z'
labels:
  - audit
  - include
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IncludeProcessor#process_includes does deep_merge(result, included_config) so the included file wins. Upstream External::Processor: merge_external_files! then append_inline_content! (@content.deep_merge!(@values)) -> the main/inline file wins; later includes win over earlier includes.
Repro: .gitlab-ci.yml: include: [local: inc.yml]; job1: {script: echo main}. inc.yml: job1: {script: echo included, tags: [x]}. Ours: script 'echo included'. Upstream: script 'echo main', tags [x]. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Main file wins over includes; later includes win over earlier ones (nested includes recursively the same)
- [x] #2 Hashes deep-merge, arrays replace
- [x] #3 Spec reproducing the repro above
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Write spec reproducing repro (red). 2. Rewrite process_includes to merge includes in order then main on top (main wins, later include wins), deep_merge hash-merge/array-replace in one shared helper. 3. just test, just e2e, review+update goldens (proj11 dag.dot expected). 4. Commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-1: just e2e diffs CLI output for test_ci_projects against projN.output_reference/. The proj11 dag.dot golden currently PINS this bug (tooltips of build-app, integration-tests, deploy-production show the included .gitlab/ci/*.yml version instead of the main-file override). After the fix: run just e2e (expect red on proj11 dag.dot, maybe others), then just e2e-update, review git diff test_ci_projects/, and explain each golden change in the commit message. Never regenerate blindly.

Implemented: process_includes now merges includes in order into an empty hash (later include wins, nested includes already expanded recursively), then merges the including file on top (it wins). Single merge primitive lib/config_merge.rb (ConfigMerge.deep_merge: hashes merge, everything else replaced, output shares no structure with inputs) replaces the private IncludeProcessor#deep_merge; TASK-6 reuses it.
Bite: new 'merge precedence' specs on pre-fix code: 5 examples, 4 failures (later-over-earlier already passed). After: green. Full rspec 550 examples, 0 failures, 47 pending (just test exits 2 on SimpleCov, TASK-2).
Goldens: proj11 dag.dot tooltips now show the main-file overrides (build-app/integration-tests/deploy-production) = the fix; proj11/proj20 dag.dot, lint.json, dry-run(.stderr) otherwise only permute job order, because key order now follows upstream deep_merge! (included keys first, main-only keys appended). dry-run schedule permutes because the simulator dispatches in config order ignoring stages (TASK-7).
Gotchas: deep_merge is NOT associative (hash, non-hash, hash on one key) so merge tree order must match upstream exactly; do not 'simplify' into a flat fold. Key order is observable in lint/dag/dry-run output. Empty included file still crashes (already listed in TASK-21).
<!-- SECTION:NOTES:END -->
