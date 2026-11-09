---
id: TASK-16
title: 'Lint parity: add missing YamlProcessor validations and fix false rejects'
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:55:00Z'
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
