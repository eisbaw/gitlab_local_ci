---
id: TASK-70
title: MR pipeline with source == target branch is accepted
status: To Do
assignee: []
created_date: '2026-11-09T23:23:00Z'
labels:
  - audit
  - hardening
dependencies: []
priority: low
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From QA: --pipeline merge_request_event --ref main gives source == target == main silently; upstream cannot create such an MR. Reject with a clear error or document.
<!-- SECTION:DESCRIPTION:END -->
