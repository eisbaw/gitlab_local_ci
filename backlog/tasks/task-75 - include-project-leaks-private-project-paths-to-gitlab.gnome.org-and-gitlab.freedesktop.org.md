---
id: TASK-75
title: >-
  include:project leaks private project paths to gitlab.gnome.org and
  gitlab.freedesktop.org
status: To Do
assignee: []
created_date: '2026-11-10T10:14:00Z'
labels:
  - audit
  - security
  - include
dependencies: []
priority: high
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From docs fact-check: ExternalResourceCache fetch_project_file tries KNOWN_GITLAB_INSTANCES (gitlab.com, gitlab.gnome.org, gitlab.freedesktop.org) in turn, so a private project path is sent to unrelated hosts. Upstream resolves project includes on the instance that runs the pipeline. Use one configured host (CI_SERVER_URL / --variables or derived from the origin remote), never a fan-out. Also: try_fetch_local_project_file reads ../<project>/<file> and ignores ref - document or honour ref. SECURITY.md documents current behaviour.
<!-- SECTION:DESCRIPTION:END -->
