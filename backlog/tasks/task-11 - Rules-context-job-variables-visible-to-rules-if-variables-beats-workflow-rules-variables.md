---
id: TASK-11
title: >-
  Rules context: job variables visible to rules:if; --variables beats
  workflow:rules:variables
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T20:13:00Z'
labels:
  - audit
  - rules
  - variables
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MockServer#filter_jobs_by_rules uses only global+predefined vars; upstream Seed::Build evaluate_context includes job yaml_variables (Context::Build#build_variables), respecting inherit:variables. Workflow rules:variables applied after CLI vars, but upstream precedence puts pipeline (CLI/trigger) variables above workflow/YAML vars (Chain::Seed#root_variables). Repros in audit (job var JOBV used in its own rules:if -> ours excluded).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Job-level variables (after default/inherit) are in the job's rules:if context
- [ ] #2 Precedence matches doc/ci/variables/_index.md: CLI > rules:variables > job > workflow rules vars > global
- [ ] #3 Specs per precedence level
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-9 (8dc4b74): evaluate_rules now builds each job's rules view as predefined < inherited root variables < CLI, via a block passed to filter_jobs_by_rules; root = root_variables(config) merged with the matched workflow rule's variables (apply_workflow_rules now returns only those), filtered by inherit:variables (PipelineBuilder.inherited_root_variables, upstream Variables::Helpers#inherit_yaml_variables). CLI-over-workflow precedence holds. Remaining for TASK-11: overlay the job's own variables: between root and CLI (upstream yaml_variables = inherited root + job vars), i.e. in that block.
<!-- SECTION:NOTES:END -->
