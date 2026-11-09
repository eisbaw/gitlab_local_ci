---
id: TASK-3
title: just update-gitlab cannot reach newer releases in the shallow submodule
status: To Do
assignee: []
created_date: '2026-11-09T17:53:00Z'
labels:
  - audit
  - tooling
dependencies: []
priority: low
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Recipe does 'git fetch && git checkout $(git describe --tags --abbrev=0)'. In the shallow clone describe returns the current tag, so it never updates. Manual update used: git ls-remote --tags to find latest vX.Y.Z-ee, git fetch --depth 1 origin tag <tag>, checkout. Submodule was moved v17.5.0-ee -> v19.5.3-ee on 2026-11-09 (old dirty state is in the submodule's git stash).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 just update-gitlab [TAG] fetches latest stable -ee tag (or given TAG) shallowly and checks it out
- [ ] #2 Refuses to run on a dirty submodule worktree
<!-- AC:END -->
