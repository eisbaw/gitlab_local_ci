---
id: TASK-5
title: 'Include merge order reversed: included file overrides main file'
status: To Do
assignee: []
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T17:54:00Z'
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
