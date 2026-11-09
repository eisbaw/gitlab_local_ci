---
id: TASK-73
title: 'lint: hidden templates are not jobs (list, count, warning)'
status: Done
assignee: []
created_date: '2026-11-09T23:24:00Z'
updated_date: '2026-11-09T23:29:00Z'
labels:
  - audit
  - lint
dependencies: []
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lint lists/counts hidden keys ('.foo') as jobs and warns about them. Upstream Entry::Jobs types them Entry::Hidden (not visible, not relevant): not in the job list, no warning. Use PipelineBuilder::Result#jobs.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LintCommand validates and lists PipelineBuilder::Result#jobs (visible jobs) instead of #job_definitions. Hidden keys (upstream Entry::Hidden: not visible, not relevant, never an Entry::Job) are no longer in lint's job list/count (text, json; junit lists no jobs), no longer warned about, and no longer validated as jobs. Upstream emits no warning for hidden keys; its only hidden-key check is presence (blank '.tpl: {}' errors) - not implemented, noted on TASK-16. Side effects matching upstream: needs: [.tpl] is now an undefined-need error in lint; a file with only hidden keys fails lint. Goldens: proj11/12/13/20 lint.json/lint.txt lose hidden jobs and their warnings only (mechanically checked).
<!-- SECTION:FINAL_SUMMARY:END -->
