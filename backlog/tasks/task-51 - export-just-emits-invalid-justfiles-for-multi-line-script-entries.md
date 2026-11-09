---
id: TASK-51
title: export-just emits invalid justfiles for multi-line script entries
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T21:19:00Z'
updated_date: '2026-11-09T22:39:00Z'
labels:
  - audit
  - export-just
dependencies: []
priority: medium
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-38 verification. export-just now runs on all 20 test projects, but just --evaluate rejects 3 of the 40 outputs (graph+flat): proj6 (heredoc 'cat > f << EOF' in test:unit: '<?xml' at column 1, 'unknown start of token'), proj7 (multi-line 'cat > Dockerfile' block: 'FROM alpine:3.19'), proj20 (block scalar: 'inconsistent leading whitespace'). Root cause: format_recipe writes each script entry as one recipe line ('    ' + entry), so a multi-line entry spills unindented lines into the justfile. Semantics are also off for single-line entries: just runs every recipe line in its own shell, GitLab runs the whole before_script+script in one shell (cd, exported vars, set -e persist). Likely fix: shebang recipes (#!/usr/bin/env bash, set -eo pipefail, entries verbatim, after_script separately) - an output-format decision, so review it as such. Verify with just --justfile <out> --evaluate on every test project (do not execute recipes).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 just --list, --evaluate and --dry-run of every recipe pass for all 20 test projects, graph and flat
- [x] #2 before_script+script run in one shell; multi-line entries intact; {{ escaped
- [x] #3 Variables exported and after_script semantics as run (TASK-22), via the shared JobEnvironment
- [x] #4 --shell wired or removed
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Shebang recipes rendering the shared JobEnvironment: exports, cd project dir, main script in its own bash -c with set -eo pipefail, after_script in a second shell with CI_JOB_STATUS; entries verbatim via quoted heredoc; {{ escaped; graph deps from MockPipeline.previous_jobs. Remove unused --shell. Verify all 20 projects with just --list/--dry-run/--evaluate; execute echo recipes from a scratch fixture.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in 79ef1d8. Output-format decision (reviewed as such): one shebang recipe per job (#!/usr/bin/env bash): export of JobEnvironment#variables (single-quoted; a snapshot at export time - CI_COMMIT_SHA etc.: regenerate after committing), cd to the absolute project dir, main script embedded verbatim with IFS= read -r -d '' VAR <<'GITLAB_CI_CLI_SCRIPT_EOF' (a script line equal to the delimiter is an error) and run by bash -c with the runner prelude (pipefail/errexit/noclobber off) and stdin /dev/null; after_script likewise in a second bash -c with CI_JOB_STATUS=success|failed under coreutils timeout <after_script_timeout_s> when present, failure reported and ignored; recipe exits with the script's code. Two shells inside one recipe (not a trap): errexit cannot be used in the outer shell because a subshell/function on the left of || ignores set -e, so the outer shell has no -e and each phase is its own process. {{ -> {{{{ on every body line; each multi-line value/entry is split and indented line by line (just strips the recipe indent, relative indentation kept). Graph deps = MockPipeline#previous_jobs minus when: on_failure jobs (just models the success path; manual/always jobs run as in dry-run/run); needs: [] -> no deps (was: stage fallback). Recipe-name clash or invalid identifier start -> error / '_' prefix. --shell removed (CLI, DEFAULTS, help; was never read).
Verification: all 20 projects x graph/flat: export ok, just --list, --evaluate, --dry-run <recipe> for all 183 recipes: pass (was: proj6/7/20 rejected). bash -n of every recipe body and (via bash -n -c substitution) of all 180 embedded scripts: pass. Executed: scratch echo fixture recipes (build, deploy with deps; exit codes 0 and 3) give the same output as run. Specs: spec/integration/export_just_spec.rb (5, executes recipes with just from the dev shell): all red on parent.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
export-just writes one shebang recipe per job from the shared JobEnvironment (79ef1d8): variables exported, one bash for before_script+script with errexit/pipefail and multi-line entries intact, after_script in a second bash with CI_JOB_STATUS, {{ escaped, graph deps from the dry-run scheduler. All 40 justfiles of the 20 test projects pass just --list/--evaluate/--dry-run (183 recipes) and bash -n; echo recipes executed match run. --shell removed. Specs red on parent.
<!-- SECTION:FINAL_SUMMARY:END -->
