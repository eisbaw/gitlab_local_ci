---
id: TASK-76
title: rules evaluation is slow on large configs (proj20 dag 4.6s, dry-run 5.3s)
status: To Do
assignee: []
created_date: '2026-11-10T10:14:00Z'
labels:
  - audit
  - performance
dependencies: []
priority: medium
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From docs fact-check: each changes: rule spawns 3 git processes and each exists: rule walks the whole tree (lib/rules_evaluator.rb), uncached. Cache git diff/ls-files results per pipeline build; measure before/after on proj20 and mesa.
<!-- SECTION:DESCRIPTION:END -->
