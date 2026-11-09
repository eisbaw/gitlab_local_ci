---
id: TASK-53
title: Commands copy CLI options field by field and silently drop new Context fields
status: To Do
assignee: []
created_date: '2026-11-09T22:14:00Z'
labels:
  - audit
  - architecture
dependencies: []
priority: medium
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-10: RunCommand#validate_options and ExportJustCommand rebuild the options hash key by key, so --ref never reached PipelineBuilder::Context in run/export-just (fixed for :ref in 7a4b351). Any future Context field will be dropped the same way, silently. Fix the class: build the Context once from the parsed CLI options (Context.from_options at the integration site) and pass the Context to every command, or have commands merge defaults into the given options instead of whitelisting keys. A parity spec per Context field (like the TASK-10 --ref parity examples) catches regressions.
<!-- SECTION:DESCRIPTION:END -->
