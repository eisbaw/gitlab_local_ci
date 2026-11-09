---
id: TASK-40
title: Bound YAML alias expansion (billion-laughs) before !reference resolution
status: To Do
assignee: []
created_date: '2026-11-09T19:57:00Z'
labels:
  - audit
  - hardening
dependencies: []
priority: medium
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ReferenceResolver#deep_resolve copies every alias: 6-level bomb 1.8s (was 5.6ms at f66d648), 7-level 18.5s, x10 per level. Upstream Gitlab::Config::Loader::Yaml checks deep_size/depth before tag resolution. Port that limit into CiYaml.load.
<!-- SECTION:DESCRIPTION:END -->
