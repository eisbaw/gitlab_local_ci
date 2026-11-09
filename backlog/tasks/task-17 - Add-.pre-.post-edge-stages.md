---
id: TASK-17
title: Add .pre/.post edge stages
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T21:52:00Z'
labels:
  - audit
  - config
dependencies:
  - TASK-1
priority: medium
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
We do not inject .pre/.post: 'stage: .pre' is undefined; user-listed .pre mid-list kept in place. Upstream Config::Stages.wrap_with_edge_stages (replaced EdgeStagesInjector since v17.5) always puts .pre first and .post last. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .pre/.post usable without declaring, always first/last
- [x] #2 Pipeline of only .pre/.post jobs handled like upstream
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PipelineBuilder.stages(config): upstream Config::Stages.wrap_with_edge_stages (.pre first, .post last, removed from user position; absent stages -> .pre build test deploy .post; non-Array/empty left as is like inject_edge_stages!). Result#stages and MockServer#create_pipeline derive from it (no stored copy).
2. Fold TASK-50: one stage check in resolve_config on composed visible jobs (default stage test included), upstream YamlProcessor wording; drop lint's and MockServer#validate_job_configs' copies.
3. Only-.pre/.post rule (Chain::Populate#no_pipeline_to_create?): after rules, if no kept job is outside .pre/.post the pipeline is empty: kept edge jobs move to excluded_jobs with upstream's message, so every command treats it like 'rules left no jobs' (TASK-36 owns that convention).
4. Specs red on parent; just e2e-update, review proj11 + stage-list goldens.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in 732515b (with TASK-50). PipelineBuilder.stages(config) derives the stage list (wrap_with_edge_stages; absent -> .pre build test deploy .post; empty list left alone); Result#stages and MockServer#create_pipeline use it. Only-.pre/.post rule (Chain::Populate): kept edge jobs move to excluded_jobs with upstream's rules_failure_message, so each command reports it like 'rules left no job' (TASK-36 owns the convention: dry-run says 'No jobs defined in configuration' exit 1, dag/export-just print empty output exit 0, run refuses the job with the reason).
Verification: spec/unit/pipeline_builder_stages_spec.rb + parity context '.pre/.post edge stages'. 18/20 new examples red on parent; the 2 guards each killed by a mutant. Suite 729/0/47 on main and in a detached worktree, just test exit 0, just e2e green. Goldens: every lint stage list gains .pre/.post (script-checked, nothing else); proj11 lint 1->0, dry-run simulates again, dag draws verify-includes in .pre. External gitlab-runner config: '.pre' error gone (remaining errors are parallel:matrix needs names).
Gotcha: dag skips stages without jobs, so .pre/.post clusters appear only when used. Several commands still hard-code the default job stage 'test' (export_just_command, run_command, dag_command) instead of composing stage: into the job: follow-up filed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
.pre/.post are implicit first/last stages (upstream wrap_with_edge_stages) and a pipeline of only .pre/.post jobs is not created (Chain::Populate). Stage check unified in PipelineBuilder with upstream wording (closes TASK-50). 732515b.
<!-- SECTION:FINAL_SUMMARY:END -->
