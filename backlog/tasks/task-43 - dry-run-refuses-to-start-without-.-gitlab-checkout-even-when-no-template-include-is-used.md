---
id: TASK-43
title: >-
  dry-run refuses to start without ./gitlab checkout even when no template
  include is used
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T20:12:00Z'
updated_date: '2026-11-09T20:55:00Z'
labels:
  - audit
  - dry-run
  - good-enough
dependencies: []
priority: high
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by COMPASS 2026-11-09: lib/commands/dry_run_command.rb validate_prerequisites requires a ./gitlab directory unless --gitlab-dir is given, even if the config has no include: template. lint and dag don't need it. In a normal user repo dry-run fails on first use. Require the gitlab dir only when a template include is actually resolved, with a clear error naming --gitlab-dir.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 dry-run works in a repo without gitlab/ when no template include is used
- [x] #2 template include without a gitlab dir gives a clear error naming --gitlab-dir
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Drop the unconditional gitlab-dir check from DryRunCommand#validate_prerequisites and the unused gitlab_path validation in MockServer (nothing reads it). 2. Make the include:template path the only place that needs the checkout: PipelineBuilder passes the configured templates dir to IncludeProcessor even when missing; IncludeProcessor#fetch_template_include fails with an error naming --gitlab-dir when the dir does not exist (before any cache/network fallback, which would silently use gitlab.com master instead of the pinned checkout). 3. Specs: dry-run from a tmp cwd without gitlab/ succeeds; template include without the dir fails naming --gitlab-dir in lint and dry-run. 4. just test, just e2e.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done. dry-run no longer checks the gitlab dir up front; MockServer's gitlab_path param was unused apart from an existence check and is gone. include:template is the only consumer: PipelineBuilder passes <gitlab-dir>/lib/gitlab/ci/templates even when missing and IncludeProcessor fails before any cache/network lookup with "include:template needs a GitLab source checkout ('<path>' not found); pass --gitlab-dir <path to gitlab repo>". Same for lint/dag/run/export-just (shared path). Behaviour change: without a checkout, templates are no longer silently downloaded from gitlab.com master (different version than the pinned checkout). With a checkout that lacks the template, the old ext_tmp/network fallback still applies (unchanged, see follow-up).
<!-- SECTION:NOTES:END -->
