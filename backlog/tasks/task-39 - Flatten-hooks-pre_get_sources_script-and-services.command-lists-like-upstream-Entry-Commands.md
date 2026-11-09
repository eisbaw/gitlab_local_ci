---
id: TASK-39
title: >-
  Flatten hooks:pre_get_sources_script and services[].command lists like
  upstream Entry::Commands
status: To Do
assignee: []
created_date: '2026-11-09T19:51:00Z'
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
