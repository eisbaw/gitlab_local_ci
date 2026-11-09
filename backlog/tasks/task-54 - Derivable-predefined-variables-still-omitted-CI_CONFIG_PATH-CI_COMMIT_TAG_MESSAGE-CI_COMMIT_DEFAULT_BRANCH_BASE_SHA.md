---
id: TASK-54
title: >-
  Derivable predefined variables still omitted: CI_CONFIG_PATH,
  CI_COMMIT_TAG_MESSAGE, CI_COMMIT_DEFAULT_BRANCH_BASE_SHA
status: To Do
assignee: []
created_date: '2026-11-09T22:14:00Z'
labels:
  - audit
  - variables
dependencies: []
priority: low
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From TASK-10: these are knowable locally but were left out to keep scope (lib/predefined_variables.rb omitted list). CI_CONFIG_PATH = entry path relative to the project root (needs entry in predefined_variables); CI_COMMIT_TAG_MESSAGE = annotated tag message in tag pipelines (git cat-file tag, signature stripped as upstream strip_signature); CI_COMMIT_DEFAULT_BRANCH_BASE_SHA = merge-base(HEAD, default branch) in non-default-branch branch pipelines. Add with specs; update the drift spec's emitted set.
<!-- SECTION:DESCRIPTION:END -->
