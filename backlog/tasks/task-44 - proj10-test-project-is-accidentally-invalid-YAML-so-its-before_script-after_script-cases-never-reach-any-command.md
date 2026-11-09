---
id: TASK-44
title: >-
  proj10 test project is accidentally invalid YAML, so its
  before_script/after_script cases never reach any command
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T20:13:00Z'
updated_date: '2026-11-09T20:29:00Z'
labels:
  - audit
  - e2e
  - test
dependencies: []
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
test_ci_projects/proj10/.gitlab-ci.yml line 41: '- echo "JOB: GLOBAL_VAR should be empty: ..."' is a plain scalar containing ': ', so YAML parses it as a mapping and every command fails with a YAML syntax error (goldens record exit 1/2). TASK-1 treated this as intentional, but the file is clearly meant to exercise global before_script/after_script override/disable (job_override_before, job_disable_before: [], ...). Found in TASK-9: defaults now apply but proj10 goldens cannot show it. Fix: quote the offending lines (and any others), regenerate proj10 goldens, review that before/after_script overrides and [] disables appear as expected in dag tooltips. If an invalid-YAML golden is wanted, keep a separate minimal project for it.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Quote every proj10 script line containing ': ' (not only line 41: unquoted 'echo "X: y"' silently parses as a mapping even where it is not a syntax error). Regenerate goldens, review that dag tooltips show global before/after_script inherited, overridden and disabled by []. Fix docs/comments that call proj10 intentionally invalid; point the expected-non-zero example at proj11 (.pre, TASK-17).
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
proj10 fixture fixed by single-quoting all 63 script lines that contain ': ' (only line 41 was a hard syntax error; the others silently parsed as mappings). Goldens regenerated and reviewed: lint valid (12 jobs, 3 stages), dag tooltips show global before/after_script inherited, per-job overrides replacing them, and [] disables preserved; dry-run runs all 12 jobs. The dry-run golden still pins TASK-7 (no stage ordering) and TASK-28 (per-tick warnings; misleading 'no eligible runner' text noted there). Docs/comments that called proj10 intentionally invalid now cite proj11's lint=1 (.pre, TASK-17). Fixture inventory for the same class in 10 other projects added to TASK-38.
<!-- SECTION:FINAL_SUMMARY:END -->
