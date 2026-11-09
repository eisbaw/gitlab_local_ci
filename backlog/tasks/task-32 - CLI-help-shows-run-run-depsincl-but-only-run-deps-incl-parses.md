---
id: TASK-32
title: CLI help shows 'run --run-deps=incl' but only '--run-deps incl' parses
status: To Do
assignee: []
created_date: '2026-11-09T18:48:00Z'
updated_date: '2026-11-09T19:24:00Z'
labels:
  - audit
  - cli
dependencies: []
priority: low
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by QA during TASK-5/6 gate: --help example uses --run-deps=incl, which fails with 'Unknown flag: --run-deps=incl'. Either accept --flag=value forms generally or fix the help text. Also: dry-run/run/export-just print resolver errors twice (once as 'Error resolving extends:' then as 'Failed to create pipeline:'/'Execution failed:'/'Export failed:'); ruby -w warns unused variable 'inputs' in lib/include_processor.rb.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Documented flag forms parse
- [ ] #2 Each error printed once
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-4 (6791beb): errors are returned as PipelineBuilder::Result#errors and printed once by dry-run, run and export-just (AC#2 part covered; spec: pipeline_parity_spec 'errors are printed once'). --run-deps=incl parsing and the ruby -w warning remain.
<!-- SECTION:NOTES:END -->
