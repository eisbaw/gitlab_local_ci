---
id: TASK-4
title: >-
  Unify config->pipeline construction so lint/dag/dry-run/run/export-just see
  the same resolved jobs
status: To Do
assignee: []
created_date: '2026-11-09T17:53:00Z'
updated_date: '2026-11-09T17:54:00Z'
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
- [ ] #1 One module produces the resolved, rule-evaluated job set from (entry, variables, pipeline context); every subcommand consumes it
- [ ] #2 Single source of reserved top-level keys and allowed job keys
- [ ] #3 Regression specs: same config yields identical job set in dag, dry-run, export-just
<!-- AC:END -->
