---
id: TASK-55
title: e2e goldens cover only push pipelines on main; no MR or tag pipeline snapshot
status: To Do
assignee: []
created_date: '2026-11-09T22:14:00Z'
labels:
  - audit
  - test
dependencies: []
priority: low
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-10: generate_output_references.sh pins one context (push, refs/heads/main). The MR/tag behaviour of the test projects' rules (proj8/12/16/20 use merge_request_event, CI_COMMIT_TAG, CI_MERGE_REQUEST_TARGET_BRANCH_NAME) is covered only by parity specs on small configs. Consider a second dag (or dry-run) snapshot per project with --pipeline merge_request_event --ref refs/heads/feature and one with --ref refs/tags/v1 so golden diffs show rule changes per pipeline type. Golden format change: decide file names first.
<!-- SECTION:DESCRIPTION:END -->
