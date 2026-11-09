---
id: TASK-43
title: >-
  dry-run refuses to start without ./gitlab checkout even when no template
  include is used
status: To Do
assignee: []
created_date: '2026-11-09T20:12:00Z'
labels:
  - audit
  - dry-run
  - good-enough
dependencies: []
priority: high
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by COMPASS 2026-11-09: lib/commands/dry_run_command.rb validate_prerequisites requires a ./gitlab directory unless --gitlab-dir is given, even if the config has no include: template. lint and dag don't need it. In a normal user repo dry-run fails on first use. Require the gitlab dir only when a template include is actually resolved, with a clear error naming --gitlab-dir.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 dry-run works in a repo without gitlab/ when no template include is used
- [ ] #2 template include without a gitlab dir gives a clear error naming --gitlab-dir
<!-- AC:END -->
