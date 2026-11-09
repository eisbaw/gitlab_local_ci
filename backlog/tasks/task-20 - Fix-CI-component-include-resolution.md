---
id: TASK-20
title: Fix CI component include resolution
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:55:00Z'
labels:
  - audit
  - include
  - feature
dependencies:
  - TASK-1
  - TASK-19
priority: medium
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
fetch_component_include requests <fqdn>/<full path incl component name>/-/raw/<ver>/template.yml. Upstream Components::InstancePath: project = path minus component name; tries templates/<name>.yml then templates/<name>/template.yml; resolves ~latest, partial semver (1.2), release tags. Network-dependent; use a local fixture server or recorded fixtures in specs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Component path/version resolution matches InstancePath for the documented forms
- [ ] #2 Specs without live network
<!-- AC:END -->
