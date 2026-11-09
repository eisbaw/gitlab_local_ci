---
id: TASK-50
title: >-
  Stage validation is per-command: lint skips jobs without stage:, dry-run
  checks it
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T21:05:00Z'
updated_date: '2026-11-09T21:52:00Z'
labels:
  - audit
  - config
dependencies: []
priority: low
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-7. lint_command validates only an explicit stage:; MockServer#validate_job_configs (dry-run) now also checks the default stage 'test' against stages:. Upstream: '<job> job: chosen stage <stage> does not exist; available stages are ...' for both. Move the stage check into PipelineBuilder (shared path) with upstream wording so lint/dag/dry-run/run/export-just agree; drop the per-command copies. Interacts with TASK-17 (.pre/.post).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done in 732515b together with TASK-17: PipelineBuilder.stage_errors runs once in resolve_config on the composed visible jobs (default stage test and extends-inherited stages included), upstream YamlProcessor wording; lint and MockServer#validate_job_configs copies deleted. dag/run/export-just now reject undeclared stages too. Specs: pipeline_builder_stages_spec 'stage check', parity 'reject an undeclared stage once, in upstream wording, in every command' (red on parent).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
One stage check in PipelineBuilder, upstream wording, every command (732515b).
<!-- SECTION:FINAL_SUMMARY:END -->
