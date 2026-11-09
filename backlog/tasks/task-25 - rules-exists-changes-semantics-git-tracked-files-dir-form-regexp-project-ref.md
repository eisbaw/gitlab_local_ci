---
id: TASK-25
title: >-
  rules:exists/changes semantics: git-tracked files, dir/ form, regexp,
  project/ref
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:55:00Z'
labels:
  - audit
  - rules
  - correctness
dependencies:
  - TASK-1
priority: low
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
exists walks the working tree (untracked/gitignored files and bare dir names match); upstream only committed files at the pipeline SHA. exists: [sub/] dir form false for us, true upstream (new). exists:regexp and changes:regexp (new RegexpMatcher, Onigmo) silently false. exists:project/ref ignored. changes: diff base unverified (we use merge-base with default branch; upstream push before-SHA / MR target, new branches/tags always changed).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 exists uses git ls-files at HEAD
- [ ] #2 dir/ and regexp forms supported
- [ ] #3 changes base documented and matched for push and MR pipelines
<!-- AC:END -->
