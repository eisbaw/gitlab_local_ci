---
id: TASK-78
title: >-
  include: host CI_SERVER_* environment variables leak into include path
  expansion
status: To Do
assignee: []
created_date: '2026-11-10T10:29:00Z'
updated_date: '2026-11-10T10:29:00Z'
labels:
  - include
  - variables
dependencies: []
priority: low
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-56. IncludeProcessor#expand_ci_variables reads ENV['CI_SERVER_FQDN'], ENV['CI_SERVER_HOST'], ENV['CI_SERVER_URL'] (falling back to gitlab.com) when expanding include:project/component paths. Rules and job variables never see host env (verified in TASK-56: grep ENV over lib/ hits only include_processor), but includes do: running inside a real CI job on a self-hosted instance silently resolves components against that instance. Decide: take these from the simulated predefined variables / --variables only, or document it as a deliberate knob (and then not under CI_* names). (GITLAB_CI_ALLOWED_DOMAINS, also read there, is documented in SECURITY.md.)
<!-- SECTION:DESCRIPTION:END -->
