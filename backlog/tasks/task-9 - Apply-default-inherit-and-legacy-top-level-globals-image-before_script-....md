---
id: TASK-9
title: >-
  Apply default:, inherit:, and legacy top-level globals (image, before_script,
  ...)
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T18:42:00Z'
labels:
  - audit
  - config
  - correctness
dependencies:
  - TASK-1
priority: high
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
default: and inherit: (default/variables true|false|list) are ignored, as are legacy top-level image/services/before_script/after_script/cache. Repro: default: {tags: [nomatch]} still gets a runner. Upstream Entry::Default, Entry::Inherit, Root legacy keys. Also run: inherit:variables false ignored for rules context. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 default keys applied to jobs unless overridden or inherit excludes them
- [ ] #2 inherit:default and inherit:variables (bool and list) honoured
- [ ] #3 Legacy top-level globals behave like default:
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-5/6: default:/inherit: merging should reuse ConfigMerge.deep_merge (lib/config_merge.rb) rather than a new merge; upstream default: keys are NOT deep-merged into jobs (job key replaces default key wholesale, see Entry::Job/Default inherit), so check before reusing. ExtendsResolver excludes 'default' from job resolution; extends inside default: is not supported upstream either.
<!-- SECTION:NOTES:END -->
