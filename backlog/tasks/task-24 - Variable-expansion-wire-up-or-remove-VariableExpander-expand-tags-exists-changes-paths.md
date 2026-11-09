---
id: TASK-24
title: >-
  Variable expansion: wire up or remove VariableExpander; expand tags,
  exists/changes paths
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T22:40:00Z'
labels:
  - audit
  - variables
  - correctness
dependencies:
  - TASK-1
priority: medium
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
VariableExpander is never used outside its spec, so --undefined MODE does nothing; expand: false parsed but unused; file-type/masked vars unsupported. tags: [$RUNNER_TAG] not expanded -> silently dropped -> job routed to untagged runner (upstream Seed::Build expand_existing). rules:exists/changes blank out undefined vars (upstream keeps literal via expand_existing, expands recursively). Cyclic-reference detection absent (upstream Collection#sort_and_expand_all).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One expansion implementation used by rules/exists/changes, tags, include locations, run
- [ ] #2 expand_existing vs expand semantics per keyword like upstream where_variables_can_be_used.md
- [ ] #3 --undefined either works or is removed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COMPASS: absorbs TASK-34 (three expand_variables copies) - same root: one expansion path. Prefer removing --undefined over wiring it.

From TASK-2: more dead code under lib/formatters: lib/formatters.rb and lib/formatters/formatter_factory.rb are required by nothing (gitlab_ci_cli.rb create_formatter picks formatters itself), and TextFormatter/JsonFormatter/JunitFormatter only ever get command: :lint, so their :dag and :dry_run branches are dead. With the honest coverage gate (all lib/ tracked) these are ~130 uncovered lines; removing them raises the line ratchet to ~88% (see the ratchet follow-up task).

From TASK-22/51 (79ef1d8): the --variables text substitution is gone from run and export-just. One copy is left: DryRunCommand#expand_variables (gsub of CLI vars only into every job value except rules if:, then drops tags still containing $VAR). Its only behavioural consumer is tags routing in dry-run; it is also what archived TASK-33 AC#2 ('dry-run jobs carry the same variables') was about, which TASK-22 did not do. Replace it with expand_existing semantics over the job's variables: lib/job_environment.rb now builds the per-job variable list in upstream order (JobEnvironment.variable_list) and has a faithful port of Collection#sort_and_expand_all + expand_value (server_expand / server_expand_value; keep_undefined matches expand_existing's keep-original), verified against upstream code. VariableExpander (lib/variable_expander.rb) is still unused; the runner-side os.Expand port in JobEnvironment is run-only (it blanks unknowns, which is right for job env, wrong for tags/exists).
<!-- SECTION:NOTES:END -->
