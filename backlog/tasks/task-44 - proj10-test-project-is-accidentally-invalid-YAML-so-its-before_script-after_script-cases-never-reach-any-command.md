---
id: TASK-44
title: >-
  proj10 test project is accidentally invalid YAML, so its
  before_script/after_script cases never reach any command
status: To Do
assignee: []
created_date: '2026-11-09T20:13:00Z'
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
