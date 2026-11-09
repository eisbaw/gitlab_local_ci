---
id: TASK-7
title: 'dry-run ignores stage ordering: jobs without needs all start at T+0'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T21:06:00Z'
labels:
  - audit
  - dry-run
  - correctness
  - good-enough
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
- [x] #1 Jobs without needs start only after all prior-stage jobs finish (honouring allow_failure)
- [x] #2 needs: [] starts immediately; needs: [x] waits only for x
- [x] #3 Spec with 3 stages + a DAG job
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
One scheduler, in MockPipeline (it owns stages+jobs); delete DryRunCommand#dependencies_satisfied?. Port upstream AtomicProcessingService semantics: previous status = Composite of needs (dag, when needs: is defined, incl. needs: []) or of all jobs in earlier stages (stage); a pending job runs when that status is complete and in ProcessBuildService#valid_statuses_for_processable for its when: (on_success/manual/delayed: stage [success skipped], dag [success]; on_failure [failed]; always [success failed skipped]); otherwise it is skipped. allow_failure failed counts as success. MockJob gets allow_failure, when, scheduling_type. extract_job_needs uses PipelineBuilder needs parsing (job: key, optional needs on absent jobs dropped, cross-pipeline needs ignored) - TASK-15 bit. Pipeline status derived from the same composite; dry-run final status uses it. Stage not in stages: config error (lint wording). Specs: 3 stages + needs: [] + needs: [build_a]; failed non-allow_failure blocks/skips; allow_failure does not; on_failure/always; map-form needs. Regenerate goldens and explain each.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-1: just e2e diffs CLI output for test_ci_projects against projN.output_reference/, including dry-run.txt (stdout timeline, simulated time). These goldens PIN this bug, e.g. proj2 dry-run.txt has build_job, test_job, deploy_job all at T+0s. After the fix expect many dry-run.txt diffs: run just e2e-update, review git diff test_ci_projects/ (each job should now start after the previous stage completes), and explain the changes in the commit message. Never regenerate blindly.

Forward-carried from TASK-4: dry-run's job set now comes from PipelineBuilder.build(...).pipeline_jobs (rule-evaluated, rule attributes applied, cascade-dropped needs removed), passed with Result#stages to MockServer#create_pipeline_from (lib/mock_server.rb). The ordering fix stays in the simulator (DryRunCommand#dependencies_satisfied? / MockPipeline), not in the builder. Result#stages defaults to PipelineBuilder::DEFAULT_STAGES (build test deploy; .pre/.post is TASK-17), the one default every command shares now. The dry-run goldens pin T+0 starts; dag goldens are unaffected by this fix.

COMPASS 2026-11-09: on the 'good enough' line (tasks that must land before claiming GitLab parity for common configs).

Done. One scheduler: MockPipeline (pending_jobs query + skip_blocked_jobs), DryRunCommand#dependencies_satisfied?/get_pending_jobs deleted. Semantics ported from upstream AtomicProcessingService/ProcessBuildService/Status::Composite: previous status = composite of needs (scheduling_type dag whenever needs: is defined, so needs: [] = empty set = success = start at once) or of every job in every earlier stage; on_success/manual/delayed accept stage [success skipped] / dag [success]; on_failure [failed]; always [success failed skipped]; otherwise the job is skipped (fixed-point loop, bounded jobs+1). allow_failure: true failed/canceled counts as success; allow_failure: {exit_codes} does not. Pipeline status and dry-run's final status come from the same composite (was a second derivation in DryRunCommand). Map-form needs fixed (TASK-15 bit). Job with a stage not in stages: is a config error with lint's wording -> proj11 dry-run now exits 1 on stage '.pre' (TASK-17). Limits: dry-run never fails a job, so failure paths are exercised by specs only; manual/delayed run like on_success (TASK-49).
<!-- SECTION:NOTES:END -->
