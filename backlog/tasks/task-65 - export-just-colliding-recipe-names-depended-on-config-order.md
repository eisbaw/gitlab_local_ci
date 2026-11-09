---
id: TASK-65
title: 'export-just: colliding recipe names depended on config order'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T23:22:00Z'
updated_date: '2026-11-09T23:22:00Z'
labels:
  - audit
  - export-just
  - correctness
dependencies: []
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When sanitised job names collided ('a b', 'a/b' -> a_b), the first job in config order kept a_b and later ones got a_b-2, a_b-3: reordering or deleting a job silently re-pointed a recipe name at another job. Fix: every member of a collision set gets '_' + first 6 hex of SHA-256 of its job name; none keeps the bare name; non-colliding names unchanged. History note: commit 79ef1d8 (pushed) says recipe-name clashes are an error; that has been outdated since the -2 numbering and is superseded by this task. Pushed history is not rewritten; this note is the correction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every member of a collision set gets a hash suffix from its own name; non-colliding names unchanged
- [x] #2 Reordering jobs changes no recipe-to-job mapping (spec, red on parent)
- [x] #3 README and docs/upgrade_guide.md document the rule; upgrade note for removed --shell
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in e8a7ceb. recipe_names = recipe_base per job, tally, colliding bases get _<sha256(name)[0,6]> for every member; residual duplicate (24-bit suffix clash or a job literally named like a suffixed one) raises naming the jobs -> export exits 1. All 20 test_ci_projects export byte-identical justfiles vs 4c2f318 apart from timestamp/output header (no collisions there). Reorder spec runs every recipe in 5 permutations of 6 jobs; red on parent (a_b-2/a_b-3 swap). README Parallel jobs section corrected (was: -2/-3 in config order); docs/upgrade_guide.md Unreleased breaking changes: collision naming + removed --shell. CHANGELOG.md not touched: unmaintained since v0.1.0.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Colliding export-just recipe names are now order-independent: every member of a collision set gets '_' + 6 hex of SHA-256 of its own job name, none keeps the bare name, non-colliding names unchanged. Documented in README and the upgrade guide (with the --shell removal); 79ef1d8's outdated 'clashes are an error' wording is corrected here, not by rewriting history.
<!-- SECTION:FINAL_SUMMARY:END -->
