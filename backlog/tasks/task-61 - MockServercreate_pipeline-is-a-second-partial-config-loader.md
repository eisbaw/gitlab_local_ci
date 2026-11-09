---
id: TASK-61
title: MockServer#create_pipeline is a second, partial config loader
status: To Do
assignee: []
created_date: '2026-11-09T23:21:00Z'
labels:
  - audit
  - hardening
dependencies: []
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MockServer#create_pipeline(config, options) (lib/mock_server.rb) loads a YAML string/hash itself: parse_configuration -> compose_jobs -> expand_parallel -> stage_errors -> evaluate_rules. It skips steps PipelineBuilder.resolve_config runs: commands_errors (script nesting depth/type errors) and flatten_lists (nested script lists), and it calls PredefinedVariables.build(project_dir:, pipeline_source:) without options[:ref], so rules see the checkout's ref, not the requested one, while create_pipeline_from does get ref. Two loaders drift: every fix to resolve_config must be repeated here or it silently differs. Proposed fix: split resolve_config so its post-load half takes a parsed hash (resolve_config(entry) = load_yaml + includes + that half), and MockServer#create_pipeline calls it with a Context carrying ref/variables; delete the private pipeline. Spec: a config with a nested script list and one with a 11-deep nested list, and a rules: if: $CI_COMMIT_REF_NAME == 'x' job with ref 'x', give the same jobs/errors via MockServer and PipelineBuilder.build (red today).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MockServer#create_pipeline runs the same post-load steps as PipelineBuilder.resolve_config (one code path)
- [ ] #2 options[:ref] reaches predefined variables in MockServer pipelines
- [ ] #3 Parity spec MockServer vs PipelineBuilder.build on nested lists, commands errors and a ref rule, red on the parent
<!-- AC:END -->
