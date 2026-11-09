---
id: TASK-5
title: 'Include merge order reversed: included file overrides main file'
status: To Do
assignee: []
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T18:08:00Z'
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
- [ ] #1 Main file wins over includes; later includes win over earlier ones (nested includes recursively the same)
- [ ] #2 Hashes deep-merge, arrays replace
- [ ] #3 Spec reproducing the repro above
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-1: just e2e diffs CLI output for test_ci_projects against projN.output_reference/. The proj11 dag.dot golden currently PINS this bug (tooltips of build-app, integration-tests, deploy-production show the included .gitlab/ci/*.yml version instead of the main-file override). After the fix: run just e2e (expect red on proj11 dag.dot, maybe others), then just e2e-update, review git diff test_ci_projects/, and explain each golden change in the commit message. Never regenerate blindly.
<!-- SECTION:NOTES:END -->
