---
id: TASK-39
title: >-
  Flatten hooks:pre_get_sources_script and services[].command lists like
  upstream Entry::Commands
status: To Do
assignee: []
created_date: '2026-11-09T19:51:00Z'
updated_date: '2026-11-09T20:12:00Z'
labels:
  - audit
  - config
dependencies: []
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during TASK-8. PipelineBuilder.flatten_lists (lib/pipeline_builder.rb, JOB_LIST_KEYS/ROOT_LIST_KEYS) flattens the upstream Entry::Commands / ComposableArray lists that consumers here read: script, before_script, after_script, rules, needs, services, cache, stages, workflow:rules. Upstream also uses Entry::Commands for hooks:pre_get_sources_script (entry/hooks.rb) and a service's command (entry/service.rb), and ComposableArray for ports (entry/ports.rb). Nothing here reads those yet, so they stay nested if built from !reference or a YAML alias. Add them when a consumer appears (run / export-just of hooks).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Nested lists in hooks:pre_get_sources_script and services[].command are flattened, with a spec
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From architect review of TASK-31/8: add rules[].needs (Entry::Needs upstream; probe: anchor-nested rules:needs -> [["a"]], needs_job_names silently drops the Array -> lost DAG edge), hooks:pre_get_sources_script, services[].command. Fix the overclaiming 'every consumer sees flat lists' comment in PipelineBuilder.flatten_lists to name deliberately-excluded keys.

Dropped per COMPASS 2026-11-09: no consumer of hooks/services command yet; rules[].needs flatten moved to TASK-15.
<!-- SECTION:NOTES:END -->
