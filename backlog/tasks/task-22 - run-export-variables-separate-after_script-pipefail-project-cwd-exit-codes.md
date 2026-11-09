---
id: TASK-22
title: >-
  run: export variables, separate after_script, pipefail, project cwd, exit
  codes
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T22:14:00Z'
labels:
  - audit
  - run
  - correctness
  - good-enough
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
Forward-carried from TASK-10 (7a4b351): run must export the predefined variables to the job shell. Source: PipelineBuilder.predefined_variables(context) (pipeline set, incl. CI, GITLAB_CI, CI_COMMIT_*, CI_PROJECT_*, MR vars only in MR pipelines) merged with PredefinedVariables.job_variables(name:, stage:, when_value:) (CI_JOB_NAME/_SLUG/GROUP_NAME/STAGE/MANUAL), then root (inherit-filtered) and CLI variables on top, as evaluate_rules does; reuse PipelineBuilder.job_predefined_variables. Unset means not exported (do not export ''). Job-only runner variables (CI_JOB_ID, CI_JOB_TOKEN, CI_JOB_STATUS, CI_JOB_TAGS, CI_PIPELINE_ID, CI_BUILDS_DIR, ...) are not in the predefined set: decide which a local run sets (CI_JOB_STATUS for after_script at least) and document. CI_PROJECT_DIR is the project dir. RunCommand#validate_options copies options field by field (it dropped :ref until 7a4b351): pass new Context fields through.
<!-- SECTION:NOTES:END -->
