---
id: TASK-83
title: origin URL read honours the user's git url.insteadOf
status: To Do
assignee: []
created_date: '2026-11-10T11:31:00Z'
labels:
  - include
  - variables
dependencies: []
priority: low
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-75 review. PredefinedVariables reads origin via 'git remote get-url origin', which applies global/user url.<base>.insteadOf rewrites: host-environment input that changes CI_PROJECT_PATH and the include:project instance. Now documented in SECURITY.md. Decide whether to read the raw remote.origin.url (git config --get) instead, and what the right answer is for users who rely on insteadOf.
<!-- SECTION:DESCRIPTION:END -->
