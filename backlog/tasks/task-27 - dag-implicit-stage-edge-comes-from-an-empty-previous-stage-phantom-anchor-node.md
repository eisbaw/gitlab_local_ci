---
id: TASK-27
title: >-
  dag: implicit stage edge comes from an empty previous stage (phantom anchor
  node)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T18:07:00Z'
updated_date: '2026-11-09T20:33:00Z'
labels:
  - dag
  - bug
dependencies: []
priority: medium
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
generate_dependency_edges in lib/commands/dag_command.rb links a job without needs to stages[i-1] even when that stage has no jobs. With default stages (build,test,deploy) and only a test job (test_ci_projects/proj1) the dot output contains '__stage_anchor_build -> test [ltail=cluster_build]' with no cluster_build; graphviz prints 'Warning: cluster named cluster_build not found' on every just e2e. Upstream semantics: a job waits for all jobs in all earlier stages, so empty stages are skipped. Fix: use the nearest earlier stage that has jobs; none -> no edge. The proj1 dag.dot golden pins the current wrong output (found in TASK-1).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No edge references a stage cluster that is not emitted
- [x] #2 proj1 dag.dot golden updated via just e2e-update and the change explained in the commit
- [x] #3 rspec covers a pipeline with an empty middle stage
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Implicit stage edge comes from the nearest earlier stage that has jobs (same set generate_dot emits clusters for); none -> no edge. Spec: empty middle stage, all-earlier-empty (proj1), seeded randomised layouts asserting no edge names an unemitted cluster/anchor and each needs-less job links to the nearest populated earlier stage. Red first, mutants checked. Regenerate proj1 golden.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
generate_dependency_edges now takes the implicit edge from the nearest earlier populated stage (nearest_populated_stage_before), using the same stage set generate_dot emits clusters for; no populated earlier stage -> no edge. 3 new specs in dag_command_spec (empty middle stage; all earlier stages empty = proj1; 40 seeded random layouts checking edges match the expected set and never reference unemitted clusters/anchors). Red on parent (3/3), green after; mutants 'first populated stage' and 'immediate previous stage' both killed. Only golden change: proj1 dag.dot loses the phantom edge from __stage_anchor_build (dag.svg regenerated accordingly). just e2e green and prints no 'cluster named ... not found' warning. Follow-up TASK-45: one compound edge from the nearest stage hides waits on earlier stages when that stage's jobs use needs: [].
<!-- SECTION:FINAL_SUMMARY:END -->
