---
id: TASK-21
title: >-
  Include edge cases: variables in locations, URL strings, globs, limits,
  validation, project context, integrity
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T20:12:00Z'
labels:
  - audit
  - include
  - correctness
dependencies:
  - TASK-1
priority: medium
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
- local: ci/$CI_PROJECT_NAME.yml not expanded (upstream Mapper::VariablesExpander).
- include: 'https://...' treated as local (upstream Normalizer -> remote).
- Glob matching the including file -> 'Circular include detected'; upstream LocationExpander skips parent (new).
- We cap nesting depth 150 with cycle check; upstream counts total files (Verifier#verify_max_includes!, 150) - 200 flat includes pass for us.
- Empty included file crashes (nil[]); upstream 'is empty or does not exist!'.
- include: inc.txt accepted; upstream requires .yml/.yaml.
- Project include without ref fetches master; upstream HEAD. Nested local: inside project include resolves against our repo, upstream switches context. file: without project: crashes.
- include:integrity (sha256 SRI) ignored (new since v17.5).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each item has a spec matching upstream
- [ ] #2 No crashes on malformed includes; upstream-style errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COMPASS: trim to empty-file crash + $VAR in local:; integrity and 150-file count are low value.
<!-- SECTION:NOTES:END -->
