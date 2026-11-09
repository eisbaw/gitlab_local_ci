---
id: TASK-38
title: 'Script entries that YAML-parse as a mapping: lint accepts, export-just crashes'
status: To Do
assignee: []
created_date: '2026-11-09T19:23:00Z'
updated_date: '2026-11-09T19:52:00Z'
labels:
  - audit
  - lint
  - export-just
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
- [ ] #1 lint reports the upstream script error for non-string entries
- [ ] #2 export-just never crashes on it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-8 (cca6a10): proj12's export-just crash (Array script entries) is fixed by flatten_lists; it came from '- *alias' list items, not !reference. Remaining crashes are Hash entries: proj6/8/9/11/13/15/17/18/20 (checked with pinned main/push context).
<!-- SECTION:NOTES:END -->
