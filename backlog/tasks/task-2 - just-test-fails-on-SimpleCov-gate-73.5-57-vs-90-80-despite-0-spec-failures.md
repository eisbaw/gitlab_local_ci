---
id: TASK-2
title: >-
  just test fails on SimpleCov gate (73.5%/57% vs 90%/80%) despite 0 spec
  failures
status: To Do
assignee: []
created_date: '2026-11-09T17:53:00Z'
labels:
  - audit
  - testing
dependencies: []
priority: medium
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
540 examples, 0 failures, but spec/spec_helper.rb minimum_coverage line 90 / branch 80 fails the run (exit 2). Likely new code (run, export-just commands) landed without specs. Do not lower the gate as a workaround; add meaningful specs, or if the gate is deliberately aspirational, decide that explicitly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 just test exits 0 with the coverage gate honoured
- [ ] #2 Any gate change is an explicit, justified decision in the commit message
<!-- AC:END -->
