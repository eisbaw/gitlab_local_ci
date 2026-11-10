---
id: TASK-77
title: Child-pipeline execution and runner exporter are unreachable from any command
status: To Do
assignee: []
created_date: '2026-11-10T10:14:00Z'
labels:
  - audit
  - cleanup
dependencies: []
priority: low
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From docs fact-check: lib/child_pipeline_handler.rb and lib/runner_exporter.rb (which needs the gitlab gem, Gemfile) are referenced only by their own specs. Decide: wire into a command, or move to cruft/ and drop the gitlab gem from the Gemfile.
<!-- SECTION:DESCRIPTION:END -->
