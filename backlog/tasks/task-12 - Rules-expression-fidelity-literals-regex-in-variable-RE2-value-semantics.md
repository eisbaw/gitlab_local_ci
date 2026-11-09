---
id: TASK-12
title: >-
  Rules expression fidelity: literals, regex-in-variable, RE2, &&/|| value
  semantics
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:54:00Z'
labels:
  - audit
  - rules
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RulesEvaluator diverges from Gitlab::Ci::Pipeline::Expression:
- 'GAP 7' code expands $VAR inside string literals and /regex/ (parse_unary, build_regex); upstream Lexeme::String/Pattern never expand (job_rules.md: variables in regex are not expanded).
- Regex stored in a variable ($REF =~ $PAT with PAT='/^fea/') not turned into a pattern (Matches#evaluate -> Pattern.build_and_evaluate). $X =~ $UNSET: upstream false, ours true. $UNSET =~ /^$/: upstream true, ours false. Non-/../ RHS is substring check upstream.
- Ruby regex vs upstream RE2 (UntrustedRegexp::RubySyntax): ^/$ anchor whole text (multi-line CI_COMMIT_MESSAGE), m flag meaning, lookbehind/backrefs invalid, only flags [ismU]. Fix the wrong code comment claiming Onigmo for if:.
- && / || return operand values then .present?: $EMPTY && $SET true, $EMPTY || $SET false upstream; whitespace-only value is false upstream.
Upstream spec: gitlab/spec/lib/gitlab/ci/pipeline/expression/statement_spec.rb - consider porting its table as fixtures. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Port upstream statement_spec.rb expression table (where non-Rails) and pass it
- [ ] #2 No variable expansion inside literals
- [ ] #3 RE2-compatible semantics or an explicit error for unsupported constructs
<!-- AC:END -->
