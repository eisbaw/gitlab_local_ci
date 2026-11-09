---
id: TASK-7
title: 'dry-run ignores stage ordering: jobs without needs all start at T+0'
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T18:08:00Z'
labels:
  - audit
  - dry-run
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
dry_run_command.rb dependencies_satisfied? returns true when a job has no needs, so build/test/deploy start simultaneously. MockPipeline#dependencies_satisfied? has stage logic but dry-run does not use it. Upstream: a job without needs waits for all jobs in previous stages (needs: [] means start immediately).
Repro: stages [build, test]; b (build), t (test) -> ours both T+0.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jobs without needs start only after all prior-stage jobs finish (honouring allow_failure)
- [ ] #2 needs: [] starts immediately; needs: [x] waits only for x
- [ ] #3 Spec with 3 stages + a DAG job
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-1: just e2e diffs CLI output for test_ci_projects against projN.output_reference/, including dry-run.txt (stdout timeline, simulated time). These goldens PIN this bug, e.g. proj2 dry-run.txt has build_job, test_job, deploy_job all at T+0s. After the fix expect many dry-run.txt diffs: run just e2e-update, review git diff test_ci_projects/ (each job should now start after the previous stage completes), and explain the changes in the commit message. Never regenerate blindly.
<!-- SECTION:NOTES:END -->
