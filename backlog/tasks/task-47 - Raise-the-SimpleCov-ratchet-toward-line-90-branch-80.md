---
id: TASK-47
title: Raise the SimpleCov ratchet toward line 90 / branch 80
status: To Do
assignee: []
created_date: '2026-11-09T20:47:00Z'
labels:
  - testing
  - coverage
dependencies: []
priority: low
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-2 made the coverage gate honest (CLI subprocesses measured, every lib/ file tracked) and set it to the measured floor: line 84 / branch 73 (measured 84.34/73.85 on main, 84.34/73.95 detached). Raise minimum_coverage in spec/spec_helper.rb to the new floor whenever specs add coverage; never lower it. Lowest-covered files (line%/branch%, honest measure, at TASK-2): lib/formatters/formatter_factory.rb 0/- and lib/formatters.rb 0/- (dead, nothing requires them -> TASK-24); lib/formatters/text_formatter.rb 34/32 and junit_formatter.rb 36/29 (the dag/dry_run branches are dead, only lint uses formatters -> TASK-24); lib/commands/run_command.rb 67/41 (semantics rework in TASK-22 first); lib/include_processor.rb 68/65 (remote/component/template paths, TASK-20/21); lib/indifferent_hash.rb 69/22; lib/commands/lint_command.rb 85/65 (error texts change in TASK-16); lib/commands/export_just_command.rb 89/64 (TASK-23); lib/rules_evaluator.rb 91/75 (TASK-12/13); lib/mock_pipeline.rb 89/71; lib/commands/dry_run_command.rb 90/76. Rough sizing: deleting the dead formatter code alone takes line coverage to ~88%. Also: just test-file FILE always fails the gate (a subset cannot reach a whole-suite minimum); consider enforcing the minimum only on full runs. Per-file numbers: rspec, then SimpleCov::ResultMerger.merged_result.files.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 minimum_coverage raised to the measured floor at least once, with the before/after numbers in the commit
- [ ] #2 Specs added assert behaviour (upstream semantics where they exist), no coverage filters added
<!-- AC:END -->
