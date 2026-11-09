---
id: TASK-28
title: >-
  dry-run: stuck pipeline exits 0 and logs one warning per pending job per
  simulated second
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T18:07:00Z'
updated_date: '2026-11-09T21:13:00Z'
labels:
  - audit
  - dry-run
  - good-enough
dependencies: []
priority: high
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
test_ci_projects/proj13 (jobs tagged docker+build/test/deploy, no runner in ./runners has those tags) ends 'Pipeline status: stuck' after MAX_ITERATIONS=10000 simulated seconds, exit code 0, and writes ~110k 'Warning: [T+Ns] Job X waiting (no eligible runner)' lines (7 MB) to stderr. Two problems: (1) a stuck pipeline is a failure and should exit non-zero (fail fast); better still, detect 'no runner can ever take this job' at T+0 instead of spinning 10000 ticks; (2) the warning should be emitted once per job, not per tick. TASK-1's e2e drops dry-run stderr for this reason; once fixed, consider snapshotting dry-run stderr too. Also check whether proj13 should get a matching runner (fixture intent is extends, not runner matching).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Stuck pipeline exits non-zero
- [x] #2 No-eligible-runner warning is printed at most once per job
- [x] #3 Goldens regenerated and reviewed (proj13 dry-run.exit_code)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. RunnerFleet#eligible_runners(job): runners whose tags take the job and max_jobs > 0 (could ever run it). 2. DryRunCommand: when a ready job gets no runner, classify once per job per reason: no eligible runner -> one Warning naming the job's tags (or untagged/run_untagged); eligible runners all busy -> one stdout timeline line 'queued', not a warning. No per-tick output. 3. Deadlock detection: a tick with nothing running and nothing skipped can never change state, so stop there instead of spinning to MAX_ITERATIONS. 4. Stuck pipeline: summary per stuck job on stderr (runner reason, or the unfinished jobs it waits for, capped), exit 1. failed/canceled status also exit 1. MAX_ITERATIONS kept as a bound, exit 1 with its own message. 5. Specs, goldens (proj13 exit 1, stderr capped tiny), then corpus table.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COMPASS 2026-11-09: every external_projects dry-run (10/10 that run) ends 'stuck' at max iterations with exit 0 - without this no dry-run result on a real config is meaningful. Raised to high.

From TASK-44: the per-tick warning text 'waiting (no eligible runner)' is also misleading - assign_job_to_runner logs it whenever find_available_runner returns nil, which includes 'eligible runners exist but are at capacity' (proj10 golden: runner_001 busy with 4 jobs, the rest log 'no eligible runner'). Distinguish 'no runner matches tags' (stuck, fail fast) from 'all matching runners busy' (normal queueing, no warning).

Done. Stuck detection: a tick with nothing running and nothing skipped can never change state (capacity only frees when a job finishes), so the loop stops there: proj13 stops at T+0 instead of T+10000. Exit 1 for stuck, failed/canceled, and MAX_ITERATIONS (now only reachable by a pipeline still progressing). Summary on stderr, one line per pending job: 'no runner has tags [..]' / 'it has no tags and no runner has run_untagged: true' for a ready job (asserted: nothing runs, so no eligible runner may exist, else capacity leak), or 'waits for <unfinished previous jobs>' capped at 5 + 'and N more'. Wait reporting once per job per reason: no eligible runner (RunnerFleet#eligible_runners empty) -> one Warning; eligible but busy -> one stdout timeline line 'queued: every runner that can take it is busy' (was the misleading per-tick 'waiting (no eligible runner)', TASK-44 note). proj13 keeps its unmatched tags: it now pins the stuck path (exit 1, 16 stderr lines). dry-run stderr was already snapshotted; only proj11/proj13 have stderr goldens now. Corpus (after TASK-7+28, --gitlab-dir gitlab --runners runners, cwd=scratch so ext_tmp/ stayed out of the submodules): 9/11 stuck with named tags (saas-linux-*, kvm, windows, macos, igalia farm, veloren/*), each in <1 s (mesa 265 jobs 0.98 s); gitlab: error, '.pre' stage (TASK-17); gnome-builder: error, component include returns HTML/auth (TASK-20). None completes with ./runners - honest, not a simulator bug. spec/fixtures/yaml/complex_pipeline.yml was always stuck on spec/fixtures/runners (security_scan [docker, security], deploy_production [deploy, production]) and passed only because stuck exited 0; those examples now use a fleet that has the tags.
<!-- SECTION:NOTES:END -->
