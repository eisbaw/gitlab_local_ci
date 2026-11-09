---
id: TASK-28
title: >-
  dry-run: stuck pipeline exits 0 and logs one warning per pending job per
  simulated second
status: To Do
assignee: []
created_date: '2026-11-09T18:07:00Z'
labels:
  - dry-run
  - bug
dependencies: []
priority: medium
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
test_ci_projects/proj13 (jobs tagged docker+build/test/deploy, no runner in ./runners has those tags) ends 'Pipeline status: stuck' after MAX_ITERATIONS=10000 simulated seconds, exit code 0, and writes ~110k 'Warning: [T+Ns] Job X waiting (no eligible runner)' lines (7 MB) to stderr. Two problems: (1) a stuck pipeline is a failure and should exit non-zero (fail fast); better still, detect 'no runner can ever take this job' at T+0 instead of spinning 10000 ticks; (2) the warning should be emitted once per job, not per tick. TASK-1's e2e drops dry-run stderr for this reason; once fixed, consider snapshotting dry-run stderr too. Also check whether proj13 should get a matching runner (fixture intent is extends, not runner matching).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Stuck pipeline exits non-zero
- [ ] #2 No-eligible-runner warning is printed at most once per job
- [ ] #3 Goldens regenerated and reviewed (proj13 dry-run.exit_code)
<!-- AC:END -->
