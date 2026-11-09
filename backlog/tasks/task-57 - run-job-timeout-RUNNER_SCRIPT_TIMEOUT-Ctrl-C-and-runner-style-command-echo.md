---
id: TASK-57
title: 'run: job timeout:, RUNNER_SCRIPT_TIMEOUT, Ctrl-C and runner-style command echo'
status: To Do
assignee: []
created_date: '2026-11-09T22:39:00Z'
labels:
  - run
dependencies: []
priority: low
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-22. run enforces only the after_script timeout (5m / RUNNER_AFTER_SCRIPT_TIMEOUT). Not modelled: the job timeout: keyword (upstream default 1h project setting) and RUNNER_SCRIPT_TIMEOUT (runner common/build.go getStageTimeoutContexts), CI_JOB_TIMEOUT. Ctrl-C during a job propagates Interrupt out of RunCommand#execute and prints a Ruby backtrace instead of a clean 130; an after_script running in its own process group does not get the terminal's SIGINT and is only killed by the ensure. The runner also echoes each command ($ cmd, collapsed multi-line) and section markers; run prints only the commands' own output.
<!-- SECTION:DESCRIPTION:END -->
