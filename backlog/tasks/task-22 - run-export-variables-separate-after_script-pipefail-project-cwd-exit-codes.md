---
id: TASK-22
title: >-
  run: export variables, separate after_script, pipefail, project cwd, exit
  codes
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T22:39:00Z'
labels:
  - audit
  - run
  - correctness
  - good-enough
dependencies:
  - TASK-1
priority: high
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Confirmed: run job with variables G (global), J (job) echoes G=[] J=[] CI=[] - no YAML, default or CI_* variables reach the shell; --variables are text-substituted into YAML (even inside single quotes) and never exported (printenv empty). Upstream: Variables::Builder scoped_variables, BuildRunnerPresenter#runner_variables, runner exports.
- before/script/after joined in one bash -e: after_script skipped on failure, shares state, no CI_JOB_STATUS. Upstream: after_script separate shell, runs on failure, own timeout.
- no pipefail (runner shells/bash.go sets it); cwd is caller dir not project dir; exits 1 instead of job exit code; hidden .template jobs runnable; rules not evaluated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Job env contains predefined + global + job + rules vars with upstream precedence; no text substitution of scripts
- [x] #2 after_script runs in a separate shell after failure with CI_JOB_STATUS
- [x] #3 set -eo pipefail; cwd = project dir; exit code propagated
- [x] #4 Only echo-based specs; no docker
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. lib/job_environment.rb (pure): per-job ordered variable list (job predefined < pipeline predefined < root vars filtered by inherit:variables, workflow vars over root < job vars incl rules:variables < CLI), expand: false = raw; server sort_and_expand_all(keep_undefined) port, then runner JobVariables.Expand (os.Expand) port; script phases main = before_script+script, after_script. 2. PipelineBuilder::Result carries predefined_variables + workflow_variables. 3. run: drop text substitution; bash -c with set -eo pipefail (runner Finish line), env exported, cwd project dir, after_script separate shell with CI_JOB_STATUS, 5m timeout, errors ignored (AFTER_SCRIPT_IGNORE_ERRORS default); exit code propagated; allow_failure/exit_codes. 4. --run-deps via MockPipeline (same previous_jobs as dry-run: needs: [] = no deps), drive when: on_failure/always with real results. 5. Echo-only specs, bite on parent.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-10 (7a4b351): run must export the predefined variables to the job shell. Source: PipelineBuilder.predefined_variables(context) (pipeline set, incl. CI, GITLAB_CI, CI_COMMIT_*, CI_PROJECT_*, MR vars only in MR pipelines) merged with PredefinedVariables.job_variables(name:, stage:, when_value:) (CI_JOB_NAME/_SLUG/GROUP_NAME/STAGE/MANUAL), then root (inherit-filtered) and CLI variables on top, as evaluate_rules does; reuse PipelineBuilder.job_predefined_variables. Unset means not exported (do not export ''). Job-only runner variables (CI_JOB_ID, CI_JOB_TOKEN, CI_JOB_STATUS, CI_JOB_TAGS, CI_PIPELINE_ID, CI_BUILDS_DIR, ...) are not in the predefined set: decide which a local run sets (CI_JOB_STATUS for after_script at least) and document. CI_PROJECT_DIR is the project dir. RunCommand#validate_options copies options field by field (it dropped :ref until 7a4b351): pass new Context fields through.

Implemented in 79ef1d8 (+ ratchet 0a53036). Shared piece lib/job_environment.rb (pure): JobEnvironment.build(result, name, cli_variables:, project_dir:) -> Job{variables, main_script, after_script, after_script_timeout_s, project_dir, warnings}; export-just (TASK-51) renders the same Job. PipelineBuilder::Result gains predefined_variables + workflow_variables (build only).
Variables: upstream append order, last wins: runner base (CI_SERVER=yes, CI_JOB_STATUS=running) < job predefined (job_predefined_variables) < pipeline predefined < yaml (job vars incl. rules:variables, then root+workflow vars filtered by inherit:variables) < CLI. Unset predefined stay unset. Job-only runner vars decided: CI_SERVER and CI_JOB_STATUS set; CI_PROJECT_DIR = project dir (already predefined); CI_BUILDS_DIR, CI_CONCURRENT_*, CI_JOB_TIMEOUT, CI_JOB_IMAGE, CI_JOB_ID/TOKEN, CI_PIPELINE_ID not set (documented in RUNNER_BASE_VARIABLES).
Expansion: port of Collection#sort_and_expand_all(keep_undefined: true, expand_file_refs: false, expand_raw_refs: false) then runner JobVariables.Expand (Go os.Expand). NOTE vs the brief: unknown refs survive step 1 but the runner blanks them, so the shell sees '' (and $$ -> $). expand: false = raw in both steps. Cycle: warning, values unexpanded (upstream runner_variables does the same, silently). Differential tests (not in the suite, they need upstream's Collection loaded standalone and Go from nixpkgs): server step identical to upstream code on 9000 random lists incl. 211 cycles; os.Expand byte-identical to Go 1.26 on 5021 inputs; spec pins Go's outputs for 23 edge cases.
Phases: SHELL_PRELUDE = runner BashWriter#Finish lines; main = before_script+script in one bash -c, stdin /dev/null, cwd project dir; after_script in a second bash -c, also after failure, CI_JOB_STATUS=success|failed, own process group, killed at RUNNER_AFTER_SCRIPT_TIMEOUT (Go duration; default 5m) - errors/timeouts reported, result unchanged (AFTER_SCRIPT_IGNORE_ERRORS default true). Exit code = first not-allowed failure's code, else 0. allow_failure true / {exit_codes} via MockJob#finish.
Deps: --run-deps incl = MockPipeline of the target + transitive previous_jobs (same scheduler as dry-run: needs: [] = none), driven with real outcomes; when: on_failure/always implemented (cheap via skip_blocked_jobs/pending_jobs). excl runs the job regardless of needs/when. Hidden jobs/rule-excluded refused as before; trigger jobs refused as target, reported+success as deps.
Specs: spec/unit/job_environment_spec.rb (52), spec/integration/run_spec.rb (17, echo/cd/exit/sleep/printenv only, invoked from /), mock_job_spec exit codes (5). Bite: on parent 057ba11 the unit spec cannot load; 23/27 behaviour examples fail; the 4 passing guard unchanged behaviour (multi-line entry, DAG needs in old resolver, excl ignores when, simulator exit_codes). Suite 854/0/47 main and detached (just test exit 0, coverage 88.24/81.83, ratchet raised to 88/81). just e2e green, no golden changes.
TASK-33 AC#2 (dry-run jobs carry the same variables) is NOT done here: dry-run still text-substitutes CLI vars (only consumer: tags routing) - left to TASK-24, noted there.
Follow-ups filed: TASK-56 (host CI_* env leaks into job), TASK-57 (job timeout:/RUNNER_SCRIPT_TIMEOUT, Ctrl-C, command echo), TASK-58 (manual jobs default allow_failure: true).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
run executes a job like a GitLab Runner shell executor (79ef1d8): variables exported from lib/job_environment.rb (predefined + global/workflow filtered by inherit:variables + job + rules:variables + CLI in upstream precedence; GitLab sort_and_expand_all then runner os.Expand, both verified against upstream/Go by differential tests; expand: false raw); no text substitution; before_script+script in one bash with errexit/pipefail in the project dir; after_script in a separate bash after failure too, with CI_JOB_STATUS and the 5m/RUNNER_AFTER_SCRIPT_TIMEOUT limit; job exit code propagated; allow_failure and exit_codes honoured; --run-deps uses the dry-run scheduler (needs: [] fixed, when: on_failure/always decided by real outcomes). Echo-only specs bite (23/27 + unit spec red on parent). Suite 854/0/47 main and detached, e2e green, ratchet 88/81. Left: dry-run variables (TASK-24), TASK-56/57/58.
<!-- SECTION:FINAL_SUMMARY:END -->
