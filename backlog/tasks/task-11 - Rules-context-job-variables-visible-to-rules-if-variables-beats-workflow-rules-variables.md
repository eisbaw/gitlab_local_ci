---
id: TASK-11
title: >-
  Rules context: job variables visible to rules:if; --variables beats
  workflow:rules:variables
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:54:00Z'
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
