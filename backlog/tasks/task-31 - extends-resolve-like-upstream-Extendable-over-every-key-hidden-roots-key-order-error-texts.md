---
id: TASK-31
title: >-
  extends: resolve like upstream Extendable over every key (hidden roots, key
  order, error texts)
status: To Do
assignee: []
created_date: '2026-11-09T18:41:00Z'
labels:
  - audit
  - config
dependencies: []
priority: low
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing TASK-6. Upstream Extendable iterates every top-level key (Extendable#each) and extends any Hash with :extends. Ours (ExtendsResolver#resolve_extends) only resolves non-hidden, non-reserved jobs: (1) a hidden template chain deeper than 11 that no job uses errors upstream ('nesting too deep') but passes ours; hidden templates are left unresolved in our output. (2) resolve_extends rebuilds the hash as config.reject(jobs).merge(resolved_jobs), moving every job after templates/globals; upstream keeps key order (observable in lint jobs list and dry-run dispatch order). (3) Unknown-parent and circular messages differ from upstream ('<key>: unknown keys in `extends` (...)', '<key>: circular dependency detected in `extends`'); a non-Hash base is reported as 'not defined' instead of 'invalid base hashes'. Ref gitlab/lib/gitlab/ci/config/extendable{,/entry}.rb at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Hidden templates resolved and depth/circular checks applied from every key, matching upstream
- [ ] #2 Key order preserved through extends resolution (goldens reviewed)
- [ ] #3 Error texts match upstream; specs for each
<!-- AC:END -->
