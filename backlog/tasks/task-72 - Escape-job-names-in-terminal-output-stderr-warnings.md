---
id: TASK-72
title: Escape job names in terminal output (stderr warnings)
status: To Do
assignee: []
created_date: '2026-11-09T23:23:00Z'
labels:
  - audit
  - hardening
dependencies: []
priority: medium
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-60 limits: job names printed in stderr warnings are not escaped, so terminal escape sequences in a CI config can reach the terminal. Use the same control-char escaping as export-just comment_text for user-facing messages.
<!-- SECTION:DESCRIPTION:END -->
