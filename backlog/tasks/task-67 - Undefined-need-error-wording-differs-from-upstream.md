---
id: TASK-67
title: Undefined-need error wording differs from upstream
status: To Do
assignee: []
created_date: '2026-11-09T23:23:00Z'
labels:
  - audit
  - hardening
dependencies: []
priority: low
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From QA of TASK-17..18: ours "Job 'nomatch' needs undefined job 'mx: [azure]'"; upstream yaml_processor.rb "#{name} job: undefined need: #{dep}". Predates the range but TASK-18 makes it far easier to hit (needs:parallel:matrix values that match nothing).
<!-- SECTION:DESCRIPTION:END -->
