---
id: TASK-45
title: >-
  dag: single stage-edge hides waits on earlier stages when the nearest stage's
  jobs have needs: []
status: To Do
assignee: []
created_date: '2026-11-09T20:32:00Z'
labels:
  - dag
  - bug
dependencies: []
priority: low
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-27. A job without needs waits for every job in every earlier stage (upstream). dag draws one compound edge from the nearest earlier populated stage only, relying on transitivity through that stage. Transitivity breaks when jobs in that stage have needs: [] (or needs that skip earlier stages): stages a,b,c; A in a; B in b with needs: []; C in c without needs. Upstream C waits for A and B; the DOT shows only cluster_b -> C and nothing links A to C. Fix idea: add a compound edge from each earlier populated stage that is not already reachable through the drawn edges (transitive reduction over the real dependency relation), not one edge per stage pair.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every upstream wait (job without needs -> all jobs of earlier stages) is reachable in the drawn graph
- [ ] #2 No redundant edges where transitivity already holds (proj goldens unchanged unless a hidden wait existed)
<!-- AC:END -->
