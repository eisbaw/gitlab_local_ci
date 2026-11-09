---
id: TASK-24
title: >-
  Variable expansion: wire up or remove VariableExpander; expand tags,
  exists/changes paths
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:55:00Z'
labels:
  - audit
  - variables
  - correctness
dependencies:
  - TASK-1
priority: medium
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
VariableExpander is never used outside its spec, so --undefined MODE does nothing; expand: false parsed but unused; file-type/masked vars unsupported. tags: [$RUNNER_TAG] not expanded -> silently dropped -> job routed to untagged runner (upstream Seed::Build expand_existing). rules:exists/changes blank out undefined vars (upstream keeps literal via expand_existing, expands recursively). Cyclic-reference detection absent (upstream Collection#sort_and_expand_all).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One expansion implementation used by rules/exists/changes, tags, include locations, run
- [ ] #2 expand_existing vs expand semantics per keyword like upstream where_variables_can_be_used.md
- [ ] #3 --undefined either works or is removed
<!-- AC:END -->
