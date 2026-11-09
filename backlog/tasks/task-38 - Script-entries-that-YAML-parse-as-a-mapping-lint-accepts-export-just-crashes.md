---
id: TASK-38
title: 'Script entries that YAML-parse as a mapping: lint accepts, export-just crashes'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T19:23:00Z'
updated_date: '2026-11-09T21:19:00Z'
labels:
  - audit
  - export-just
  - good-enough
dependencies: []
priority: medium
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-4. Unquoted ': ' in a script line, e.g. - echo "body { color: blue; }" in test_ci_projects/proj6, parses as a Hash. Upstream rejects ('script config should be a string or a nested array of strings up to 10 levels deep'); our lint only checks the outer Array, and export-just crashes with "undefined method 'gsub' for an instance of Hash" on 9 of 20 test projects (proj6/8/9/11/13/15/17/18/20; proj12/20 also hit !reference Arrays, TASK-8). Decide whether the fixtures are wrong (quote them) and make lint/dry-run/export-just report the upstream error instead of crashing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 lint reports the upstream script error for non-string entries
- [x] #2 export-just never crashes on it
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PipelineBuilder.commands_errors(config): upstream Entry::Commands (StringOrNestedArrayOfStringsValidator, max_level 10) for root before/after_script, default:before/after_script and every visible job's script/before_script/after_script, on the resolved config before flatten_lists (flattening would hide nesting depth); message '<location> config should be a string or a nested array of strings up to 10 levels deep', downcased like upstream Validator#messages. All errors reported, resolve_config fails -> lint, dag, dry-run, run, export-just reject alike. Drop lint's now-dead own script type check. 2. Quote the affected fixture lines (TASK-44 style, single quotes, keep the command text). 3. Specs per location + nesting depth + every command rejects. 4. e2e-update, explain goldens; export-just --evaluate on all 20 projects.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-8 (cca6a10): proj12's export-just crash (Array script entries) is fixed by flatten_lists; it came from '- *alias' list items, not !reference. Remaining crashes are Hash entries: proj6/8/9/11/13/15/17/18/20 (checked with pinned main/push context).

COMPASS 2026-11-09: on the 'good enough' line (tasks that must land before claiming GitLab parity for common configs).

From TASK-44: proj10 fixed by quoting (all its ': ' lines). Fixture inventory of remaining Hash script entries (YAML scan of test_ci_projects/**/*.yml for script/before_script/after_script items that are not String/Array): proj6, proj8, proj9, proj11 (+.gitlab/ci/test.yml, deploy.yml), proj13, proj15, proj16 (.gitlab/ci/child1.yml), proj17, proj18, proj20 (+.gitlab/ci/monitoring.yml). Lint says 'valid' for all of them; upstream would reject. When lint is fixed, these goldens flip to invalid unless the fixtures are quoted in the same change.

Done. PipelineBuilder.commands_errors (upstream Entry::Commands / StringOrNestedArrayOfStringsValidator, max_level 10) runs in resolve_config after extends/!reference and before flatten_lists, over root and default: before/after_script and every visible job's script/before_script/after_script; null = unspecified; hidden jobs not validated (Entry::Hidden). Text as upstream lint prints it, downcased like Validator#messages: 'jobs:<job>:script config should be a string or a nested array of strings up to 10 levels deep'. Every command reports Result#errors, so lint/dag/dry-run/run/export-just reject alike; lint's own script type check was dead after this and is gone. Fixtures: 68 lines in 13 files (proj6, 8, 9, 11 + .gitlab/ci/test.yml, deploy.yml, 13, 15, 16 .gitlab/ci/child1.yml, 17, 18, 20 + .gitlab/ci/monitoring.yml) single-quoted, inner ' doubled; a YAML round-trip gives the intended command. Goldens: only dag.dot tooltips (YAML dump of the job now shows the string quoted). export-just: exit 0 on all 20 projects (graph and flat); just --list/--evaluate pass for 17, fail for proj6/proj7/proj20 on multi-line script entries - a different, pre-existing bug (proj7 never crashed and was already invalid), filed as TASK-51.
<!-- SECTION:NOTES:END -->
