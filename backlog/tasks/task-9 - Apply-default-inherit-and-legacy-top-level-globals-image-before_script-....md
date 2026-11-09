---
id: TASK-9
title: >-
  Apply default:, inherit:, and legacy top-level globals (image, before_script,
  ...)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T20:13:00Z'
labels:
  - audit
  - config
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
default: and inherit: (default/variables true|false|list) are ignored, as are legacy top-level image/services/before_script/after_script/cache. Repro: default: {tags: [nomatch]} still gets a runner. Upstream Entry::Default, Entry::Inherit, Root legacy keys. Also run: inherit:variables false ignored for rules context. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 default keys applied to jobs unless overridden or inherit excludes them
- [x] #2 inherit:default and inherit:variables (bool and list) honoured
- [x] #3 Legacy top-level globals behave like default:
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PipelineBuilder.compose_jobs(config): pure fn applying default:/legacy globals to visible jobs (Job type: Default::ALLOWED_KEYS; trigger/bridge: interruptible only), whole-key replace, inherit:default bool/list; error when key in both legacy global and default:. 2. Result stores job_definitions (composed, config order, hidden untouched); jobs/pipeline_jobs derive from it; config stays raw. 3. Per-job rules variables: predefined + root vars (top-level + workflow:rules:variables) filtered by inherit:variables + CLI. 4. Specs that bite per semantic + parity spec + audit repro 03 sticks in dry-run. 5. just test on main and detached worktree, just e2e, review goldens.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-5/6: default:/inherit: merging should reuse ConfigMerge.deep_merge (lib/config_merge.rb) rather than a new merge; upstream default: keys are NOT deep-merged into jobs (job key replaces default key wholesale, see Entry::Job/Default inherit), so check before reusing. ExtendsResolver excludes 'default' from job resolution; extends inside default: is not supported upstream either.

Forward-carried from TASK-4: apply default:/inherit:/legacy globals in PipelineBuilder.resolve_config (lib/pipeline_builder.rb) after extends (and after !reference, TASK-8): rewrite each visible job entry in Result#config in place (not hidden templates; upstream does not apply defaults to Entry::Hidden). Then every consumer gets them: lint via Result#job_definitions, dag/run/export-just/dry-run via build's pipeline_jobs. Rules (PipelineBuilder.evaluate_rules) run after this step, as upstream: normalize before Pipeline::Chain. The legacy top-level keys are CiKeywords::ROOT (lib/ci_keywords.rb), now the only root-key list. inherit:variables also governs which top-level variables a job's rules see: PipelineBuilder.pipeline_variables builds one variable set for all jobs today; filter_jobs_by_rules overlays CI_JOB_NAME/STAGE per job, which is the place for a per-job variables view.
Seam decision (TASK-4 architect review, not implemented, no user yet): today Result#jobs/#job_definitions are derived from Result#config on demand. Once defaults apply, a job no longer equals its config entry, so store the composed jobs instead of writing defaults into config: resolve_config sets a stored Result#job_definitions (defaults applied, config order), Result#jobs and build's pipeline_jobs derive from it, and Result#config stays the raw post-extends/!reference hash (TASK-8 works on config, TASK-9 produces job_definitions). Mirrors upstream Config#to_hash vs Root#jobs_value. Pipeline variables do not reach jobs at all yet: TASK-33.

Forward-carried from TASK-31/8 (775abb7, cca6a10): resolve_config order is now load -> includes -> ExtendsResolver (every top-level key is a root, so a Hash under default: with extends: is extended too, as upstream) -> ReferenceResolver -> PipelineBuilder.flatten_lists. default: is a valid !reference target (references dig the whole config incl. globals: '!reference [default, before_script]' and '!reference [before_script]' resolve), and default:'s before_script/after_script/services/cache are already flattened by flatten_lists. When applying default:/inherit: to split jobs (your seam: composed job_definitions on Result), merge AFTER references are resolved, i.e. on Result#config, so a default value that is itself a !reference is already plain data. Upstream merges default into jobs in Entry::Job#compose! (deep_merge? no: Entry-level 'inherit' of whole keys; check entry/default.rb + inherit), not via ConfigMerge.

Implemented in 8dc4b74. PipelineBuilder.compose_jobs (after flatten_lists) applies default: + legacy globals (CiKeywords::DEFAULT/LEGACY_DEFAULT) to visible jobs: whole-key replacement (no deep merge, Job#overwrite_entry), null job key = unspecified -> inherits, hidden templates untouched, trigger jobs (Entry::Bridge = no script:/run:) inherit only interruptible (CiKeywords::BRIDGE_DEFAULT). Errors in upstream wording: legacy+default same key (InheritError), default: unknown keys / non-hash, inherit non-hash / unknown keys, inherit:default unknown values, inherit:<k> not bool/list. Result#job_definitions is STORED (composed); Result#jobs/pipeline_jobs derive; Result#config stays raw (no defaults). evaluate_rules(config, jobs:, ...) now takes jobs explicitly; MockServer#create_pipeline composes too. inherit:variables: per-job rules view = predefined < inherited root vars (top-level variables merged with workflow:rules:variables, filtered by inherit:variables) < CLI; apply_workflow_rules now returns only the matched rule's variables.
Verification: new spec/unit/pipeline_builder_defaults_spec.rb (22) + parity spec 'default: and legacy globals (TASK-9)' (lint/dag/dry-run/export-just/run). Bite: on parent 18 of the 23 new examples fail; the 5 that pass on parent are regression guards (cache whole-replace, inherit false x2, inherit:variables true, CLI not filtered) and each is killed by a mutant (deep-merge, inherit:false ignored, hidden gets defaults, bridge as job, inherit:variables false ignored, null-not-unspecified: all 6 mutants killed). Suite 637/0/47 pending on main and in a detached worktree (worktree needs its OWN nix develop; running rspec with GEM_PATH forced to the main .gems drops default gems like rexml and gives 4 junit failures - an env artefact, not a code issue). just e2e green after e2e-update: dag tooltips of proj9/11/20 gain inherited keys only (script-verified: no old key changed, job sets identical). Audit repro 03: dry-run now 'Pipeline status: stuck' (10000 waiting lines + exit 0 = TASK-28).
Lessons: (1) upstream 'inherit: true/false' on Entry::Default nodes means 'may come from a legacy top-level key', NOT 'job inherits it' - job inheritance is the inherit: flag on Entry::Job/Processable nodes. (2) Bridge jobs inherit almost nothing. (3) workflow:rules:variables are root variables, so inherit:variables:false hides them too. Known gaps: upstream keeps extends: in default: and then rejects it as unknown key; ours deletes extends during resolution so default:{extends:} is accepted (TASK-16 territory). proj10 (global before/after_script) is accidentally invalid YAML -> TASK-44.

Mutation addendum: two more mutants killed (CLI variables filtered by inherit:variables; inherit:variables true dropping all root vars), so every new example that passes on the parent is killed by at least one of 8 mutants.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
default:, legacy top-level globals and inherit:default/variables applied on the split jobs as upstream (8dc4b74): PipelineBuilder.compose_jobs, stored Result#job_definitions, per-job inherit:variables rules view. All 5 subcommands see the same composed jobs (parity spec). Specs bite (18 red on parent; 6 mutants killed). Suite 637/0/47 on main and detached; just e2e green with dag golden changes in proj9/11/20 explained in the commit. Follow-up TASK-44 (proj10 invalid YAML); notes forwarded to TASK-22, TASK-11, TASK-16.
<!-- SECTION:FINAL_SUMMARY:END -->
