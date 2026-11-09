---
id: TASK-16
title: 'Lint parity: add missing YamlProcessor validations and fix false rejects'
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T19:52:00Z'
labels:
  - audit
  - lint
  - correctness
dependencies:
  - TASK-1
  - TASK-4
priority: medium
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
False accepts (upstream rejects): need on later-stage job; duplicate needs; dependencies on undefined/later-stage job; needs on hidden job; default stage 'test' missing from stages (dag then silently drops job); only-hidden-jobs file; non-map job (foo: bar); when: bogus; rules+only; workflow when: manual; interruptible in workflow rules; unknown rule key (iff: — evaluator then treats it as unconditional match!); when: delayed without start_in; publish + pages:publish; truly unknown job keys.
False rejects: id_tokens, start_in, manual_confirmation, hooks, secrets, identity, dast_configuration, publish, run, job-level inputs (new) rejected by dry-run; run: step jobs rejected for lacking script.
Lint warnings only visible with --format json. tags: 'a' (string) crashes dry-run with NoMethodError.
Upstream: Job::ALLOWED_KEYS, PROCESSABLE_ALLOWED_KEYS, YamlProcessor#validate_job*, ci.json schema. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each listed case has a lint spec matching upstream accept/reject
- [ ] #2 Warnings shown in text output
- [ ] #3 No crash on malformed scalar-vs-list values
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-4: lint gets its jobs from PipelineBuilder.resolve_config (static config: includes, extends; no rules) through Result#job_definitions (hidden templates included). Allowed job keys are one list, CiKeywords::JOB (lib/ci_keywords.rb, a union of upstream Job + EE Job + Bridge + Processable, checked against the gitlab/ submodule by spec/unit/ci_keywords_spec.rb). Per-type Job vs Bridge checks still have to be added. Two job validators remain and disagree: LintCommand#validate_job (warnings for unknown keys) and MockServer#validate_job_configs (errors; used by dry-run). Unify them into one validator over Result jobs, consumed by both. CiKeywords.job_entry? silently skips non-Hash top-level values (foo: bar), whereas upstream errors: report them as Result#errors in resolve_config. Needs on a job that is undefined, hidden or rule-excluded are cascade-dropped silently by PipelineBuilder.cascade_drop_orphaned_needs (reason recorded in Result#excluded_jobs); upstream fails pipeline creation unless optional: true.
QA on TASK-4: unknown key (frobnicate: 1) is a lint warning (valid, exit 0) but a dry-run error; upstream rejects. A job with no script/trigger fails lint and dry-run, but dag draws it and export-just writes a placeholder, both exit 0: validation is not part of PipelineBuilder, so the builder guarantees the same job set, not the same validity. Natural home: a validation step on Result (errors as data) in lib/pipeline_builder.rb that every command reports.

Forward-carried from TASK-31/8: (1) lint now reports ExtendsResolver errors verbatim (upstream texts, no prefix) and ReferenceResolver errors verbatim; validate_extends is gone. (2) Upstream validations not done here yet: Entry::Commands 'should be a string or a nested array of strings up to 10 levels deep' (script/before_script/after_script; flatten_lists flattens any depth silently), Entry::Stages nested_array_of_strings max 10, Rules::Rule 'config should be a hash' (RulesEvaluator now raises a ParseError on a non-Hash rule at rule-evaluation time, with our own text, so lint, which does not evaluate rules, still accepts it). (3) The 2-string-array 'skip !reference' heuristic is removed from validate_needs: needs are flattened and validated as names now.
<!-- SECTION:NOTES:END -->
