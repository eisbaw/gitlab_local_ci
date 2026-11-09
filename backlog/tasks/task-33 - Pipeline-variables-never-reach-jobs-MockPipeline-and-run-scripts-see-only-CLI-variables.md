---
id: TASK-33
title: >-
  Pipeline variables never reach jobs: MockPipeline and run scripts see only CLI
  --variables
status: To Do
assignee: []
created_date: '2026-11-09T19:23:00Z'
labels:
  - audit
  - variables
  - correctness
dependencies: []
priority: medium
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-4 review. PipelineBuilder.evaluate_rules computes the pipeline variable set (predefined < top-level variables: < workflow:rules:variables < CLI) but only rules see it. MockServer#create_pipeline_from gets @options[:variables] (CLI only), and run executes scripts with no exported variables at all: echo $GLOBAL $JOBVAR $RULEVAR prints empty (QA repro scratchpad/qa4/p8.yml). Upstream exports predefined + pipeline + yaml (top-level, job, rules:variables) to the job. Plug-in: return the variable set from PipelineBuilder.build (Result field, removed in efda999 because nothing read it) and hand it to MockPipeline and RunCommand#execute_script env.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 run exports predefined, top-level, job and rules:variables to the script env with upstream precedence
- [ ] #2 dry-run jobs carry the same variables
<!-- AC:END -->
