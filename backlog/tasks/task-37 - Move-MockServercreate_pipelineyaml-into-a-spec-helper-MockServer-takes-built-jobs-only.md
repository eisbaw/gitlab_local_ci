---
id: TASK-37
title: >-
  Move MockServer#create_pipeline(yaml) into a spec helper; MockServer takes
  built jobs only
status: To Do
assignee: []
created_date: '2026-11-09T19:23:00Z'
updated_date: '2026-11-09T19:52:00Z'
labels:
  - audit
  - architecture
  - test
dependencies: []
priority: low
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-4 architect review. MockServer#create_pipeline(yaml) is a second, spec-only build path: it evaluates rules (PipelineBuilder.evaluate_rules) but skips includes/extends and will skip default:/!reference, so MockServer specs drift from the CLI as TASK-9/31/8 land. It is also the only reason MockServer keeps project_dir/pipeline_source and calls PredefinedVariables. Move it to a spec helper composing PipelineBuilder + create_pipeline_from (mechanical across ~50 spec call sites); drop the two constructor arguments.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MockServer has one creation entry point (create_pipeline_from)
- [ ] #2 Specs build pipelines through PipelineBuilder
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-4 f0cb362: the spec helper that replaces MockServer#create_pipeline(yaml) must pass PinnedPipelineContext (spec/support/pinned_pipeline_context.rb), so mock-server specs do not depend on the checkout's git state.

From TASK-8: MockServer#create_pipeline(String) is now the only YAML.safe_load of CI config left in lib/ (lib/mock_server.rb parse_configuration); it bypasses CiYaml (no !reference), includes, extends and flatten_lists. Moving it to a spec helper that goes through PipelineBuilder removes the last divergent load path.
<!-- SECTION:NOTES:END -->
