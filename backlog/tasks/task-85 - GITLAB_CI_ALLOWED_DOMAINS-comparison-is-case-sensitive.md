---
id: TASK-85
title: GITLAB_CI_ALLOWED_DOMAINS comparison is case-sensitive
status: To Do
assignee: []
created_date: '2026-11-10T11:31:00Z'
labels:
  - include
  - security
dependencies: []
priority: low
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-74 review. validate_remote_url compares uri.host to the allowlist entries with String#==; host names are case-insensitive, so GitLab.com in the list does not allow gitlab.com and vice versa (fails closed). Compare downcased; spec it.
<!-- SECTION:DESCRIPTION:END -->
