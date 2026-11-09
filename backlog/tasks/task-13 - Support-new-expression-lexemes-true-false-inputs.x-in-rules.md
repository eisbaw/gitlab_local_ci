---
id: TASK-13
title: 'Support new expression lexemes: !, true/false, $[[ inputs.x ]] in rules'
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:54:00Z'
labels:
  - audit
  - rules
  - feature
dependencies:
  - TASK-1
priority: medium
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
New since v17.5: Lexeme::Not, Lexeme::Boolean (compare_with_coercion), Lexeme::Input, UnaryOperator, LogicalOperator. Ours: 'Cannot tokenize' crashes the whole pipeline. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lexemes parsed and evaluated per upstream
- [ ] #2 Unknown tokens produce a lint error on that rule, not a crash
<!-- AC:END -->
