---
id: TASK-63
title: 'Unbounded variable expansion: server_expand exponential, os_expand quadratic'
status: To Do
assignee: []
created_date: '2026-11-09T23:22:00Z'
updated_date: '2026-11-09T23:22:00Z'
labels:
  - audit
  - hardening
dependencies: []
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobEnvironment.server_expand (lib/job_environment.rb) substitutes already-expanded values in reference order, so A: '$B$B', B: '$C$C', ... doubles per level: 30 such variables give a 2^30-character value (GBs, OOM) from a few lines of YAML. os_expand slices text[(j + 1)..] at every '$' to call go_shell_name, so a value with n '$' is O(n^2) in copying. We have no bound. (Not verified whether upstream bounds this: a grep of gitlab/lib/gitlab/ci/variables found no expansion-size limit; the runner may limit elsewhere. Our bound is a local-tool safety net either way.) Fix: (1) a cap on the expanded size per value (and total), e.g. EXPANDED_VALUE_BYTES_MAX with a unit and rationale, raising JobEnvironment::Error naming the job and the variable; (2) go_shell_name takes (text, index) instead of a slice. Spec: the doubling chain fails fast with the contextual error in well under a second; a 100k-'$' value expands in linear time (generous bound); differential results unchanged on the existing os.Expand cases.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Expanded value size is bounded; exceeding it is a contextual error naming job and variable
- [ ] #2 os_expand is linear: no slicing per '$'
- [ ] #3 Specs for the doubling chain and a large '$' value, red (time/memory) on the parent
<!-- AC:END -->
