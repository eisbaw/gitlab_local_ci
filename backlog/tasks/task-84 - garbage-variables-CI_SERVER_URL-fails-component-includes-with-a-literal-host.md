---
id: TASK-84
title: garbage --variables CI_SERVER_URL fails component includes with a literal host
status: To Do
assignee: []
created_date: '2026-11-10T11:31:00Z'
labels:
  - include
dependencies: []
priority: low
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-78 review. IncludeProcessor#server_variables parses @server_url for every component include, so --variables CI_SERVER_URL=not-a-url raises even for 'component: gitlab.com/g/c@1' that uses no $CI_SERVER_* at all. Expand lazily: parse only when the reference contains a CI_SERVER_ variable.
<!-- SECTION:DESCRIPTION:END -->
