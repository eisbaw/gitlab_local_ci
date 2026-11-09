---
id: TASK-62
title: Variables are parsed twice and the two parsers disagree
status: To Do
assignee: []
created_date: '2026-11-09T23:21:00Z'
labels:
  - audit
  - hardening
dependencies: []
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PipelineBuilder.variable_values (lib/pipeline_builder.rb, feeds rules/workflow evaluation) and JobEnvironment.yaml_variables (lib/job_environment.rb, feeds run/export-just) parse the same variables: entries differently: (1) non-Hash variables: -> variable_values returns {} silently, yaml_variables raises Error; (2) Symbol-keyed value hashes: variable_values reads v['value'] || v[:value], yaml_variables only entry['value']; (3) expand: false: yaml_variables keeps it raw, variable_values drops the flag so rules see an expanded value where the job sees the raw one; nil handling also differs in shape. Rules and the job environment can therefore disagree about a variable's value. Fix the class: one parser returning JobEnvironment::Variable (key, value, raw) with one error policy; derive the rules map (key => value) from it. Spec: a table of variables: forms (plain, nil, Integer, {value:}, {value:, expand: false}, Symbol keys, non-Hash) through both consumers, asserting rules and job environment see the same value (red today for expand:false and non-Hash).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One variables: parser; the rules map is derived from its Variables
- [ ] #2 Non-Hash variables: is one error (same text) in every command
- [ ] #3 Spec over the variables: forms shows rules and run/export-just agree, red on the parent
<!-- AC:END -->
