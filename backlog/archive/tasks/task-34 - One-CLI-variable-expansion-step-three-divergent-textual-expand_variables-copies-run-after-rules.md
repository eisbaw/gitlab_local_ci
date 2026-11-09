---
id: TASK-34
title: >-
  One CLI-variable expansion step: three divergent textual expand_variables
  copies run after rules
status: To Do
assignee: []
created_date: '2026-11-09T19:23:00Z'
updated_date: '2026-11-09T20:12:00Z'
labels:
  - audit
  - variables
  - architecture
dependencies: []
priority: low
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-4 architect review. dry_run_command.rb, run_command.rb and export_just_command.rb each gsub CLI --variables into job configs (expand_variables); only dry-run protects rules if: and filters unexpanded tags; dag/lint expand nothing, so the same job differs per command. Since TASK-4 the expansion runs on PipelineBuilder pipeline_jobs, i.e. after rules: a top-level variables: X: $CLI_VAR reaches rules unexpanded (RulesEvaluator does not expand nested references). Root fix: expand references inside PipelineBuilder.pipeline_variables (data, not text), then one post-build substitution step (or none) shared by all commands. Also Context#variables vs raw @options[:variables] are two copies of the CLI vars in each command.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Nested variable references expanded once, in PipelineBuilder
- [ ] #2 No per-command expand_variables copies
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Merged into TASK-24 per COMPASS 2026-11-09.
<!-- SECTION:NOTES:END -->
