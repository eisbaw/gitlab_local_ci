---
id: TASK-4
title: >-
  Unify config->pipeline construction so lint/dag/dry-run/run/export-just see
  the same resolved jobs
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T19:24:00Z'
labels:
  - audit
  - architecture
dependencies:
  - TASK-1
priority: high
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Subcommands each build their own view of the config, so they disagree:
- dag does not resolve extends (needs/stage from templates lost), draws hidden jobs as nodes, treats top-level image:/services: as jobs (missing from reserved list).
- dag, run, export-just do not evaluate rules (when: never jobs appear).
- include:rules variable scope differs: only dry-run passes PredefinedVariables + --variables; lint passes only --variables; dag/run/export-just pass none (repro: include gated on $CI_PIPELINE_SOURCE == "push" merged by dry-run, dropped by lint/dag).
- --project is ignored; project_path derived from entry dir.
- lint and MockServer#validate_job_configs keep separate allowed-key lists that disagree.
Upstream has one pipeline: Gitlab::Ci::Config (YAML load + !reference, includes, extends, normalizer) -> YamlProcessor -> Pipeline::Chain seeds with rules. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One module produces the resolved, rule-evaluated job set from (entry, variables, pipeline context); every subcommand consumes it
- [x] #2 Single source of reserved top-level keys and allowed job keys
- [x] #3 Regression specs: same config yields identical job set in dag, dry-run, export-just
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. refactor (no golden change): lib/ci_keywords.rb = upstream Entry::Root keys (one constant); lib/pipeline_builder.rb gets the primitives (include processing, job split, workflow/job rules moved verbatim out of MockServer). Commands keep their current composition.
2. refactor+fix(pipeline): PipelineBuilder.build(entry:, project_dir:, gitlab_dir:, pipeline_source:, variables:) -> Result; lint/dry-run/run/export-just consume it. Include rules see predefined+CLI vars everywhere (c); --project routed; errors returned as data, printed once.
3. fix(dag): dag consumes the builder (a): extends resolved, hidden jobs and top-level globals not drawn.
4. fix(dag,run,export-just): rules applied (b) via Result#pipeline_jobs; run reports rule-excluded jobs.
5. fix: one job-keyword list from upstream Job/Bridge/Processable (AC#2).
Each behaviour commit: just e2e-update, review git diff test_ci_projects/, explain every change.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-5/6: lint, dry-run, run, export-just each run process_includes then ExtendsResolver#resolve_extends via their own private copies; dag runs only includes. Unify on one function (includes -> extends -> later !reference/default) so the TASK-6 array-replace semantics reach dag tooltips too. Key order is observable (lint jobs list, dag node order, dry-run dispatch): includes now emit included keys first (upstream deep_merge! order), but resolve_extends still moves jobs after globals/templates (TASK-31).

From architect review of TASK-5/6: reserved top-level key list %w[stages variables workflow include default] duplicated twice in ExtendsResolver#resolve_extends and incomplete (top-level cache:, image, services, before_script etc. classified as jobs). Make one constant shared with command layer (also TASK-9). Hardening idea: differential property test of ConfigMerge vs ActiveSupport Hash#deep_merge as test-only oracle.

Implemented in 35af1a2 (extract primitives, no golden change), 6791beb (PipelineBuilder.build/resolve_config + Context/Result; lint, dry-run, run, export-just; include rules see predefined+CLI vars; --project routed; errors once), 9fac8c4 (dag: extends, no hidden, no globals), 589dc49 (rules in dag/run/export-just; run refuses excluded/hidden jobs with a reason), 9443d72 (CiKeywords::JOB), 16e9c82 (extends keeps key order = TASK-31 AC#2), efda999 (review fixes: optional/cross-project needs, CLI > workflow vars).
Gotchas: (1) e2e covers only lint/dag/dry-run; export-just/run need their own checks. export-just crashes on 10/20 test projects before and after (TASK-38, TASK-8), so parity there was checked on the 10 that run. (2) generate_output_references.sh now pins git context for lint and dag too, because include rules read CI_COMMIT_* in every command. (3) The --project default is the entry file's dir (CLI DEFAULTS[:project]=nil); upstream uses the repo root, documented in --help. (4) The needs cascade still drops jobs whose required need is missing; upstream errors (TASK-15). (5) Seam decision for TASK-9: store composed job_definitions on Result rather than write defaults into config (note on TASK-9).
Follow-ups filed: TASK-33 (pipeline vars never reach jobs), 34 (one variable expansion step), 35 (narrow rescue), 36 (no-pipeline exit convention), 37 (MockServer yaml path to spec helper), 38 (Hash script entries). Notes appended to 7, 8, 9, 10, 15, 16, 31, 32.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PipelineBuilder (lib/pipeline_builder.rb) is the single config->pipeline seam: resolve_config (load, includes with predefined+CLI vars, extends) for lint; build (plus workflow and job rules, excluded_jobs with reasons) for dag, dry-run, run and export-just. CiKeywords (lib/ci_keywords.rb) holds the root and job keyword lists from upstream, with drift specs. Per-command duplicates are deleted. Goldens changed only where intended, reviewed in each commit message. spec/integration/pipeline_parity_spec.rb drives the CLI and checks that dag/dry-run/export-just give identical job sets; every bite example was shown red on the parent commit. Gates on efda999: 579 examples, 0 failures, 47 pending (exit 2 = SimpleCov, TASK-2); just e2e green.
<!-- SECTION:FINAL_SUMMARY:END -->
