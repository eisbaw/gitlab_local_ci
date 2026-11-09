---
id: TASK-2
title: >-
  just test fails on SimpleCov gate (73.5%/57% vs 90%/80%) despite 0 spec
  failures
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T20:47:00Z'
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
- [x] #1 just test exits 0 with the coverage gate honoured
- [x] #2 Any gate change is an explicit, justified decision in the commit message
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Measure honestly first: SimpleCov only counted files loaded in the rspec process, so dry-run/run/export-just/formatters (driven by integration specs through bin/gitlab_ci_cli) were invisible; track_files alone gives 51% line. Measure the CLI subprocesses (RUBYOPT hook, per-pid resultsets merged once at exit, stale results cleared at start). Then add behavioural specs for valuable low-coverage code that is not about to be reworked by an open task: ExternalResourceCache (network stubbed at Net::HTTP only), runner file format + runner selection, include local globs and project file lists, CLI argument errors through the binary. Mutation-check them. Set minimum_coverage to the floor of the measured value, documented as a ratchet; file a follow-up to raise it.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC wording vs the honest fix: the configured numbers went DOWN (90/80 -> 84/73) while the measurement got STRICTER (CLI subprocesses and never-loaded lib/ files now count). Before, the 79/64 reported was in-process-loaded files only; the honest equivalent was 51% line. This is the 'decide explicitly' branch of the description: 90/80 stays the aspiration (TASK-47), the gate is a ratchet at the measured floor. Bite: rspec --exclude-pattern 'spec/integration/**/*_spec.rb' -> 61.30/69.33, exit 2.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Coverage gate made honest and green. spec/simplecov_config.rb (shared root/filters/branch/merge timeout) + spec/simplecov_cli_subprocess.rb (RUBYOPT hook: each bin/gitlab_ci_cli run spawned by a spec stores coverage in coverage/cli/<pid>/, silently) + spec_helper.rb (clears stale results, merges subprocess resultsets once at exit, track_files lib/**). Before: 79.06% line / 64.39% branch of loaded files only (51.21% line with all lib/ tracked), gate 90/80, just test exit 2. Subprocess measurement alone: 79.47/68.04. New specs (+43 examples, 640 -> 683): ExternalResourceCache (lookup order, cache write, bounded relative redirects, https-only, HTML rejection, multi-instance fallback), runner JSON format validation + real-runner selection, include local globs (* vs **, ..) and project file: lists, CLI argument errors through the binary. 10/10 mutants killed. After: 84.34/73.85 (main), 84.34/73.95 (detached); minimum set to 84/73 and documented as a ratchet. just test exit 0 on main and detached; 683/0/47 both. Follow-ups: TASK-46 (runner path that is a file says 'does not exist'), TASK-47 (raise ratchet; lowest files listed), notes on TASK-24 (dead formatter code) and TASK-30 (gem 'simplecov' mitigation).
<!-- SECTION:FINAL_SUMMARY:END -->
