---
id: TASK-22
title: >-
  run: export variables, separate after_script, pipefail, project cwd, exit
  codes
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:55:00Z'
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
