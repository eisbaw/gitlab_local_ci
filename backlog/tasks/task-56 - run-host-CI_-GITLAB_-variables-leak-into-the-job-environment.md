---
id: TASK-56
title: 'run: host CI_*/GITLAB_* variables leak into the job environment'
status: To Do
assignee: []
created_date: '2026-11-09T22:39:00Z'
labels:
  - run
  - export-just
  - variables
dependencies: []
priority: low
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-22. run spawns bash with the job's variables merged over this process's environment (like a shell executor inherits the runner's env). When the tool itself runs inside a CI job or a shell with CI_* set, a variable GitLab would leave UNSET for the simulated pipeline (e.g. CI_COMMIT_TAG in a branch pipeline, CI_MERGE_REQUEST_IID outside MR pipelines) is still visible to the job script with the host's value. Decide: unset every CI_*/GITLAB_* name not in JobEnvironment#variables before spawning (and do the same in export-just recipes with unset), or document. Same for export-just recipes, which inherit just's environment.
<!-- SECTION:DESCRIPTION:END -->
