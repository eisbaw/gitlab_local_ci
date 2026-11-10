---
id: TASK-56
title: 'run: host CI_*/GITLAB_* variables leak into the job environment'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T22:39:00Z'
updated_date: '2026-11-10T10:32:00Z'
labels:
  - run
  - export-just
  - variables
dependencies: []
priority: low
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-22. run spawns bash with the job's variables merged over this process's environment (like a shell executor inherits the runner's env). When the tool itself runs inside a CI job or a shell with CI_* set, a variable GitLab would leave UNSET for the simulated pipeline (e.g. CI_COMMIT_TAG in a branch pipeline, CI_MERGE_REQUEST_IID outside MR pipelines) is still visible to the job script with the host's value. Decide: unset every CI_*/GITLAB_* name not in JobEnvironment#variables before spawning (and do the same in export-just recipes with unset), or document. Same for export-just recipes, which inherit just's environment.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Default run/export-just hide host CI_*/GITLAB_* and arbitrary host variables; PATH, HOME etc. kept
- [x] #2 --pass-env all restores full host inheritance; --pass-env A,B passes base plus A,B; invalid names rejected
- [x] #3 Job variables beat same-named host variables in every mode; --variables still win
- [x] #4 after_script shell gets the same environment
- [x] #5 Docs (README, SECURITY, usage, --help, CHANGELOG) updated; gates green
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Default: jobs start from a minimal host base (PATH HOME USER LOGNAME SHELL LANG LC_* TERM TZ TMPDIR) plus the job's GitLab variables. --pass-env none|all|NAME,... tunes it (none default; all = old behaviour). One module lib/host_environment.rb owns the base list, the mode parser (name validation) and the host-side selection. run: Process.spawn with unsetenv_others and the explicit env, main and after_script. export-just: the recipe builds its host env at run time from the invoking env and runs both shells via env -i (env without -i under all); mode baked into the file. Docs: README Limits, SECURITY, usage.md, --help, CHANGELOG breaking. Tests bite on parent.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented as designed. lib/host_environment.rb owns BASE (one constant, per-entry rationale), the --pass-env parser and selection. run: Process.spawn(env, unsetenv_others: true) for both shells. export-just: recipe builds gitlab_ci_env=(env -i NAME=value...) at run time from exported variables of just's environment (declare -p check, ${!LC_@} for the prefix; no compgen: nixpkgs bash lacks it; no ${x@a}: bash 3.2), job variables appended (env assigns left to right, so they win); plain env under all. Mode is baked into the header and regenerate line. Rules never saw host env (grep ENV lib/: only include_processor, filed as TASK-78). Repeated --pass-env is an error rather than last-wins or merge, to avoid ambiguity. Specs: spec/unit/host_environment_spec.rb, --pass-env blocks in run_spec and export_just_spec, rejection rows in cli_arguments_spec; all 11 new integration examples red on the parent lib.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Jobs from run and export-just recipes now start from a minimal host base (PATH HOME USER LOGNAME SHELL LANG LC_* TERM TZ TMPDIR) plus their GitLab variables; --pass-env none|all|NAME,... tunes it (none default, all = old behaviour). Job variables win over host ones in every mode, --variables still win. export-just reads the names at recipe run time via env -i; the mode is baked into the file. Docs, --help, CHANGELOG (breaking) updated. just test 947/0/47 pending (main and detached worktree), e2e OK. Follow-up: TASK-78 (include expansion reads host CI_SERVER_*).
<!-- SECTION:FINAL_SUMMARY:END -->
