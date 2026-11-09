---
id: TASK-46
title: >-
  RunnerFleet#load_runners: a runners path that is a file says 'directory does
  not exist'
status: To Do
assignee: []
created_date: '2026-11-09T20:42:00Z'
labels:
  - dry-run
  - bug
dependencies: []
priority: low
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-2. lib/runner_fleet.rb checks Dir.exist?(directory) before File.directory?(directory); Dir.exist? is false for a regular file, so the 'not a directory' branch is unreachable and dry-run --runners some.json reports 'directory does not exist: some.json'. Fix: check File.exist? first, then File.directory?. spec/unit/runner_fleet_spec.rb 'rejects a missing directory and a path that is a file' then asserts /not a directory/ for the file case.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A file path is reported as 'not a directory'
- [ ] #2 Spec asserts the exact message for both cases
<!-- AC:END -->
