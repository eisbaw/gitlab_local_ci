---
id: TASK-27
title: >-
  dag: implicit stage edge comes from an empty previous stage (phantom anchor
  node)
status: To Do
assignee: []
created_date: '2026-11-09T18:07:00Z'
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
- [ ] #1 No edge references a stage cluster that is not emitted
- [ ] #2 proj1 dag.dot golden updated via just e2e-update and the change explained in the commit
- [ ] #3 rspec covers a pipeline with an empty middle stage
<!-- AC:END -->
