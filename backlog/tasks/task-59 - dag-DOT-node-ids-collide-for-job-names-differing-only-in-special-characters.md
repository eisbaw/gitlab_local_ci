---
id: TASK-59
title: 'dag: DOT node ids collide for job names differing only in special characters'
status: To Do
assignee: []
created_date: '2026-11-09T23:00:00Z'
updated_date: '2026-11-09T23:22:00Z'
labels:
  - dag
  - correctness
dependencies: []
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DagCommand#sanitize_id maps every non-[A-Za-z0-9_] char to '_', so 'a:b' and 'a/b' (or matrix instances 'build: [linux/amd64]' vs 'build: [linux-amd64]') get the same DOT node id and graphviz merges them: one node, edges of both. Parallel expansion (TASK-18) makes such names common. Fix the class: use quoted DOT ids ("build: [aws]", escaped) instead of sanitized ones; this changes every dag.dot golden's node ids, so review the e2e diff. Found while implementing TASK-18; checked: no collision in current test_ci_projects goldens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Two jobs whose names differ only in non-alphanumeric characters are two DOT nodes with their own edges
- [ ] #2 Spec with 'a:b' and 'a/b' (and two matrix instances) that is red today
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Collision handling to mirror (export-just, TASK-65, e8a7ceb): when sanitised names collide, export-just now gives EVERY member of the collision set '_' + first 6 hex of SHA-256 of its own name and none keeps the bare name, so names never depend on config order; a residual clash is an error naming the jobs. For DOT the proposed fix (quoted ids, escaped) avoids sanitisation altogether and is still preferable; if sanitised ids are kept, use the same order-independent rule, never first-come numbering.
<!-- SECTION:NOTES:END -->
