---
id: TASK-64
title: PredefinedVariables swallows git failures silently
status: To Do
assignee: []
created_date: '2026-11-09T23:22:00Z'
labels:
  - audit
  - hardening
dependencies: []
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PredefinedVariables.git (lib/predefined_variables.rb) returns nil on any non-zero exit and drops stderr; nil is also the legitimate answer for 'no such ref'. So a real failure - git refusing the repo (safe.directory / dubious ownership, common in containers and on shared checkouts) or a stray GIT_DIR/GIT_WORK_TREE in the environment - silently yields no CI_COMMIT_SHA, no ref variables, CI_PROJECT_PATH = directory name, and rules evaluate against that without a word. Fix: when 'git rev-parse' fails in a project_dir that contains .git, log once to stderr with git's own stderr (Warning: git failed in <dir>: <message>; commit/ref variables unset). Keep nil for the expected misses (show-ref --verify of an absent ref, no remote). Spec: a repo dir with GIT_DIR pointed elsewhere (and/or safe.directory refusal simulated via a wrapper git on PATH) gives exactly one warning on stderr; a plain non-git dir gives none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 rev-parse failure in a dir with .git warns once on stderr with git's message
- [ ] #2 Expected misses (absent ref, no origin, not a repo) stay silent
- [ ] #3 Spec red on the parent
<!-- AC:END -->
