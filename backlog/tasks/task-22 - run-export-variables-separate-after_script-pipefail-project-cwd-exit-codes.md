---
id: TASK-22
title: >-
  run: export variables, separate after_script, pipefail, project cwd, exit
  codes
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T20:13:00Z'
labels:
  - audit
  - run
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Confirmed: run job with variables G (global), J (job) echoes G=[] J=[] CI=[] - no YAML, default or CI_* variables reach the shell; --variables are text-substituted into YAML (even inside single quotes) and never exported (printenv empty). Upstream: Variables::Builder scoped_variables, BuildRunnerPresenter#runner_variables, runner exports.
- before/script/after joined in one bash -e: after_script skipped on failure, shares state, no CI_JOB_STATUS. Upstream: after_script separate shell, runs on failure, own timeout.
- no pipefail (runner shells/bash.go sets it); cwd is caller dir not project dir; exits 1 instead of job exit code; hidden .template jobs runnable; rules not evaluated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Job env contains predefined + global + job + rules vars with upstream precedence; no text substitution of scripts
- [ ] #2 after_script runs in a separate shell after failure with CI_JOB_STATUS
- [ ] #3 set -eo pipefail; cwd = project dir; exit code propagated
- [ ] #4 Only echo-based specs; no docker
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-9 (8dc4b74): run and export-just now get default:/legacy before_script, after_script, image, services, cache etc. already applied on Result#pipeline_jobs (PipelineBuilder.compose_jobs); do not re-apply defaults in RunCommand. A job's own before_script/after_script ([] included) replaces the default whole. When separating after_script into its own shell, read it from the composed job. inherit:variables is in each job's inherit: key; root variables a job may see = top-level variables merged with workflow:rules:variables, filtered by PipelineBuilder.inherited_root_variables (reuse it when exporting variables, with TASK-33).
<!-- SECTION:NOTES:END -->
