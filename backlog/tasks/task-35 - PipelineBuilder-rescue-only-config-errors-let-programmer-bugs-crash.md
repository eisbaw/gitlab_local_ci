---
id: TASK-35
title: 'PipelineBuilder: rescue only config errors, let programmer bugs crash'
status: To Do
assignee: []
created_date: '2026-11-09T19:23:00Z'
updated_date: '2026-11-09T20:01:00Z'
labels:
  - audit
  - hardening
dependencies: []
priority: low
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-4 architect review. PipelineBuilder.resolve_config/build rescue StandardError around includes, extends and rules, so a NoMethodError in our code is reported as 'Error evaluating rules: undefined method ...' (config error) instead of crashing with a backtrace. IncludeProcessor, ExtendsResolver and RulesEvaluator raise bare RuntimeError today. Introduce one ConfigError class raised by those three and rescue only it in lib/pipeline_builder.rb.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Bugs surface as crashes with backtrace; config errors stay Result#errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From QA of TASK-31/8: include: !reference [...] -> 'Error processing includes: undefined method key? for an instance of CiYaml::Reference' (internal error text leaks); <<: !reference -> 'undefined method reverse_each' from Psych merge-key code.
<!-- SECTION:NOTES:END -->
