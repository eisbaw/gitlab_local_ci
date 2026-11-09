---
id: TASK-48
title: >-
  include:template falls back to gitlab.com master when the checkout lacks the
  template
status: To Do
assignee: []
created_date: '2026-11-09T20:55:00Z'
labels:
  - audit
  - includes
dependencies: []
priority: low
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-43. ExternalResourceCache#fetch_template: checkout -> ext_tmp/templates cache -> download from gitlab.com master. A template missing from the pinned checkout (v19.5.3-ee) is silently fetched from master, a different version, and cached unversioned in ext_tmp/ (relative to cwd). Decide: fail with upstream's 'does not exist' error (upstream resolves templates only from its own tree), or keep the fallback but version the cache key and warn.
<!-- SECTION:DESCRIPTION:END -->
