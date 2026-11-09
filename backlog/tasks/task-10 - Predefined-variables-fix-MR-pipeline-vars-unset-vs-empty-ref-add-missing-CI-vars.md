---
id: TASK-10
title: >-
  Predefined variables: fix MR pipeline vars, unset-vs-empty, --ref, add missing
  CI vars
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T20:12:00Z'
labels:
  - audit
  - variables
  - correctness
  - good-enough
dependencies:
  - TASK-1
priority: high
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lib/predefined_variables.rb diverges:
- --pipeline merge_request sets CI_PIPELINE_SOURCE=merge_request; upstream merge_request_event.
- CI_MERGE_REQUEST_IID='' (falsy) so if: $CI_MERGE_REQUEST_IID never matches; MR vars should be set in MR pipelines.
- CI_COMMIT_BRANCH set in MR pipelines; upstream unset (HasRef#branch?).
- CI_COMMIT_TAG='' on non-tag pipelines so == null false; upstream unset.
- --ref feature-x does not affect CI_COMMIT_BRANCH.
- Missing: CI, GITLAB_CI, CI_JOB_NAME_SLUG, and v19.x additions CI_JOB_GROUP_NAME, CI_JOB_TAGS, CI_DEFAULT_BRANCH_SLUG, CI_COMMIT_MESSAGE_IS_TRUNCATED, CI_COMMIT_USER_LOGIN, CI_PROJECT_TOPICS, CI_PIPELINE_SCHEDULE_DESCRIPTION. CI_PROJECT_PATH is name only (should be namespace/name).
Upstream: gitlab/doc/ci/variables/predefined_variables.md, Enums::Ci::Pipeline, Project#predefined_variables. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Standard MR rules (if: $CI_PIPELINE_SOURCE == 'merge_request_event', if: $CI_MERGE_REQUEST_IID, if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS) evaluate like GitLab in branch, tag, MR pipelines
- [ ] #2 Variables not applicable to a pipeline type are unset, not empty
- [ ] #3 Emitted set cross-checked against predefined_variables.md
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From TASK-4 QA: --pipeline merge_request is now what include rules see in every command too (PipelineBuilder.Context, predefined vars computed once per build), so this bug now affects lint/dag/run/export-just include and job rules, not only dry-run. The parity spec's merge_request examples use the tool's own string 'merge_request'; update them when switching to merge_request_event.

Forward-carried from TASK-4 (f0cb362): specs that exercise rules pin the pipeline context via spec/support/pinned_pipeline_context.rb (PinnedPipelineContext: CI_COMMIT_BRANCH/REF_NAME/REF_SLUG/TAG/SHA/SHORT_SHA, CI_DEFAULT_BRANCH, --pipeline push), mirroring generate_output_references.sh pinned_git_context. When this task changes predefined vars (unset vs empty CI_COMMIT_TAG, merge_request_event, MR vars, --ref), update BOTH pin lists together. Pinning CI_COMMIT_TAG='' then means 'set but empty', which this task says should be unset; decide how a pin expresses 'unset'. Re-run the suite in a detached worktree and on a throwaway branch as well as on main. Also: IncludeProcessor uses ENV['CI_DEFAULT_BRANCH'] for include-rule changes: context instead of the predefined/CLI variable set.

COMPASS 2026-11-09: on the 'good enough' line (tasks that must land before claiming GitLab parity for common configs).
<!-- SECTION:NOTES:END -->
