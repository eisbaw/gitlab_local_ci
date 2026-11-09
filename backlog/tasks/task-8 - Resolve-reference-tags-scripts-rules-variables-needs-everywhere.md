---
id: TASK-8
title: Resolve !reference tags (scripts, rules, variables, needs) everywhere
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:54:00Z'
labels:
  - audit
  - config
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nothing in lib/ resolves !reference: script becomes [[".setup","script"], "echo main"]; lint skips !reference in needs; export-just crashes (undefined method gsub for Array); rules lists nested via !reference or YAML anchor (- *anchor) are skipped by RulesEvaluator#evaluate_rules (next unless rule.is_a?(Hash)), so a nested when: never is ignored. Upstream: Config::Yaml::Tags::Reference resolved after include merge, then arrays one level deep flattened (Entry::Rules#value, ComposableArray, script flattening). Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 !reference resolved after includes/extends across files, with error on missing target and cycles
- [ ] #2 Nested arrays in script/before_script/after_script/rules flattened one level like upstream
- [ ] #3 export-just no longer crashes on references
<!-- AC:END -->
