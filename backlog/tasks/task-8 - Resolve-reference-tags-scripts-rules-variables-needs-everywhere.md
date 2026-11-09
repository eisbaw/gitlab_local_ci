---
id: TASK-8
title: Resolve !reference tags (scripts, rules, variables, needs) everywhere
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T19:51:00Z'
labels:
  - audit
  - config
  - correctness
dependencies:
  - TASK-1
  - TASK-31
priority: high
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nothing in lib/ resolves !reference: script becomes [[".setup","script"], "echo main"]; lint skips !reference in needs; export-just crashes (undefined method gsub for Array); rules lists nested via !reference or YAML anchor (- *anchor) are skipped by RulesEvaluator#evaluate_rules (next unless rule.is_a?(Hash)), so a nested when: never is ignored. Upstream: Config::Yaml::Tags::Reference resolved after include merge, then arrays one level deep flattened (Entry::Rules#value, ComposableArray, script flattening). Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 !reference resolved after includes/extends across files, with error on missing target and cycles
- [x] #2 Nested arrays in script/before_script/after_script/rules flattened one level like upstream
- [x] #3 export-just no longer crashes on references
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1) One YAML loader (lib/ci_yaml.rb) parsing !reference into a frozen CiYaml::Reference marker; used by PipelineBuilder.load_yaml and IncludeProcessor. 2) lib/reference_resolver.rb: resolve after extends over the whole config (upstream Tags::Resolver), dig root config, cycle + missing + invalid errors with upstream text, memo by path. 3) PipelineBuilder flattens composable arrays (script/before_script/after_script/rules/needs/services/cache, root before/after_script, default:, workflow:rules, stages) fully, as upstream Entry values do. 4) Remove the 2-element-array heuristics in lint/mock_pipeline. 5) Specs incl. cross-file, nested, variables, rules via ref+anchor, errors, literal array, export-just.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-5/6: include merge (IncludeProcessor) and extends (ExtendsResolver) now both use lib/config_merge.rb (ConfigMerge.deep_merge, arrays replace). !reference must resolve AFTER both, against the merged+extended config, as upstream does. ConfigMerge.deep_dup returns plain Hash/Array/String copies: if !reference tags are parsed into a custom object, make sure deep_dup preserves it (today it passes non-Hash/Array/String values through by reference). mock_pipeline.rb currently skips !reference arrays; the dag tooltip in proj20 shows '- - .backend_base / - before_script', i.e. unresolved tags survive into job configs.

Forward-carried from TASK-4: add !reference resolution as one step in PipelineBuilder.resolve_config (lib/pipeline_builder.rb), right after ExtendsResolver and before the Result is built, so lint, dag, dry-run, run and export-just all see resolved references; Result#config is the single resolved config. Two YAML load sites must preserve the tag: PipelineBuilder.load_yaml (entry file) and IncludeProcessor#process_includes (included files, lib/include_processor.rb); both use YAML.safe_load today, which turns !reference into a plain Array. Rules: PipelineBuilder.filter_jobs_by_rules hands rules to RulesEvaluator.evaluate_rules; flatten nested rule arrays before that. export-just crashes on Array script entries today (proj12/proj20); that disappears once references resolve.

Implemented in cca6a10. lib/ci_yaml.rb CiYaml.load is the one loader (PipelineBuilder.load_yaml and IncludeProcessor): Psych safe_load visitor subclass, '!reference' nodes become a frozen CiYaml::Reference (Data), not global Psych.add_tag. lib/reference_resolver.rb runs once in resolve_config after extends, before the Result; dig into the whole unresolved config (Hash keys only), nested refs, memo per path, deep_dup per use site. Error texts upstream: '!reference [".a", "b"] could not be found' / 'is part of a circular chain' / '!reference ".a" is not valid'. NOTE: upstream has NO depth limit on nested !reference (only the cycle check); the docs' '10 levels' is Entry::Commands' nested-array validation (string_or_nested_array_of_strings max_level 10), which is lint parity (forwarded to TASK-16). NOTE: upstream flattens FULLY, not one level: Commands#value Array(config).flatten, ComposableArray#compose! [config].flatten (rules, needs, services, cache, include rules), Stages#value. PipelineBuilder.flatten_lists does that for job/default script/before_script/after_script/rules/needs/services/cache, root before/after_script/services/cache/stages, workflow:rules; IncludeProcessor#include_rules_match? flattens include rules. RulesEvaluator now raises ParseError on a non-Hash rule instead of skipping it. Removed the 2-string-array shape heuristics in LintCommand#validate_needs and MockPipeline#extract_job_needs. Golden change: proj12 dag.dot/svg only (before_script from '- *alias' items now flat; verified programmatically that nothing else changed). export-just: proj12 now works (its crash was nested alias lists, not !reference); proj6/8/9/11/13/15/17/18/20 still crash on Hash script entries (TASK-38). proj20 uses !reference but the referencing jobs are rule-excluded in the pinned context, so goldens do not exercise it; the specs do. Bite: spec/unit/reference_resolver_spec.rb on parent 775abb7: 20 examples, 19 failures (the literal-2-string-list guard passes on parent by design: it guards against a shape-based resolver). Suite 614/0/47 main and detached; e2e green on 7fc1509 (the amend to cca6a10 added one spec only). Limits: MockServer#create_pipeline(String) still uses YAML.safe_load and bypasses includes/extends/references (spec-only path, TASK-37). hooks/services command/ports not flattened (TASK-39). CiYaml depends on Psych::Visitors::ToRuby/ClassLoader::Restricted/ScalarScanner internals (Psych 5.1.2 pinned by the flake); spec/unit/ci_yaml_spec.rb differential test vs YAML.safe_load over repo configs and upstream templates catches drift.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
!reference is parsed into a distinct marker by one shared loader, resolved once after extends against the whole config with upstream error texts, and nested lists in script/before_script/after_script/rules/needs/services/cache/stages/workflow:rules are flattened like upstream entry values, so lint, dag, dry-run, run and export-just all see resolved, flat configs. Commit cca6a10; 614/0/47 main and detached; e2e green with one reviewed golden change (proj12 dag).
<!-- SECTION:FINAL_SUMMARY:END -->
