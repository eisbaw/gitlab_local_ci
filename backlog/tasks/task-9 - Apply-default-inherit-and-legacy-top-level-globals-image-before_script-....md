---
id: TASK-9
title: >-
  Apply default:, inherit:, and legacy top-level globals (image, before_script,
  ...)
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T19:52:00Z'
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
- [ ] #1 default keys applied to jobs unless overridden or inherit excludes them
- [ ] #2 inherit:default and inherit:variables (bool and list) honoured
- [ ] #3 Legacy top-level globals behave like default:
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-5/6: default:/inherit: merging should reuse ConfigMerge.deep_merge (lib/config_merge.rb) rather than a new merge; upstream default: keys are NOT deep-merged into jobs (job key replaces default key wholesale, see Entry::Job/Default inherit), so check before reusing. ExtendsResolver excludes 'default' from job resolution; extends inside default: is not supported upstream either.

Forward-carried from TASK-4: apply default:/inherit:/legacy globals in PipelineBuilder.resolve_config (lib/pipeline_builder.rb) after extends (and after !reference, TASK-8): rewrite each visible job entry in Result#config in place (not hidden templates; upstream does not apply defaults to Entry::Hidden). Then every consumer gets them: lint via Result#job_definitions, dag/run/export-just/dry-run via build's pipeline_jobs. Rules (PipelineBuilder.evaluate_rules) run after this step, as upstream: normalize before Pipeline::Chain. The legacy top-level keys are CiKeywords::ROOT (lib/ci_keywords.rb), now the only root-key list. inherit:variables also governs which top-level variables a job's rules see: PipelineBuilder.pipeline_variables builds one variable set for all jobs today; filter_jobs_by_rules overlays CI_JOB_NAME/STAGE per job, which is the place for a per-job variables view.
Seam decision (TASK-4 architect review, not implemented, no user yet): today Result#jobs/#job_definitions are derived from Result#config on demand. Once defaults apply, a job no longer equals its config entry, so store the composed jobs instead of writing defaults into config: resolve_config sets a stored Result#job_definitions (defaults applied, config order), Result#jobs and build's pipeline_jobs derive from it, and Result#config stays the raw post-extends/!reference hash (TASK-8 works on config, TASK-9 produces job_definitions). Mirrors upstream Config#to_hash vs Root#jobs_value. Pipeline variables do not reach jobs at all yet: TASK-33.

Forward-carried from TASK-31/8 (775abb7, cca6a10): resolve_config order is now load -> includes -> ExtendsResolver (every top-level key is a root, so a Hash under default: with extends: is extended too, as upstream) -> ReferenceResolver -> PipelineBuilder.flatten_lists. default: is a valid !reference target (references dig the whole config incl. globals: '!reference [default, before_script]' and '!reference [before_script]' resolve), and default:'s before_script/after_script/services/cache are already flattened by flatten_lists. When applying default:/inherit: to split jobs (your seam: composed job_definitions on Result), merge AFTER references are resolved, i.e. on Result#config, so a default value that is itself a !reference is already plain data. Upstream merges default into jobs in Entry::Job#compose! (deep_merge? no: Entry-level 'inherit' of whole keys; check entry/default.rb + inherit), not via ConfigMerge.
<!-- SECTION:NOTES:END -->
