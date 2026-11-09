---
id: TASK-10
title: >-
  Predefined variables: fix MR pipeline vars, unset-vs-empty, --ref, add missing
  CI vars
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T22:14:00Z'
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
- [x] #1 Standard MR rules (if: $CI_PIPELINE_SOURCE == 'merge_request_event', if: $CI_MERGE_REQUEST_IID, if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS) evaluate like GitLab in branch, tag, MR pipelines
- [x] #2 Variables not applicable to a pipeline type are unset, not empty
- [x] #3 Emitted set cross-checked against predefined_variables.md
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Data first: the pipeline identity is (source, ref kind+name, sha, default branch, project path). Bottom: PredefinedVariables.read_git (I/O only, facts or nil). Middle: pure derivation (pipeline_variables, job_variables, resolve_ref, project_path_from_remote, slugify, group_name). Top: CLI --pipeline/--ref -> Context (canonical source, ref).
1. Sources = upstream Enums::Ci::Pipeline.sources names; aliases merge_request->merge_request_event, manual->web (manual was never an upstream source).
2. Ref: --ref NAME|refs/heads/NAME|refs/tags/NAME; plain name is a tag iff a local tag exists, branch otherwise; both -> 'Ref is ambiguous'. Default: checked-out branch, else detached-at-one-tag -> tag, else unknown (ref vars unset). MR pipeline needs a branch (fail fast otherwise).
3. Unset-not-empty: CI_COMMIT_BRANCH only for branch pipelines (not MR, not tag), CI_COMMIT_TAG only for tag pipelines, MR vars only for merge_request_event; nothing unknown is emitted as ''.
4. Add CI, GITLAB_CI, CI_JOB_NAME_SLUG, CI_JOB_GROUP_NAME, CI_JOB_MANUAL, CI_DEFAULT_BRANCH_SLUG, CI_PROJECT_PATH(_SLUG)/NAMESPACE(_SLUG)/ROOT_NAMESPACE(_SLUG) from origin, CI_COMMIT_MESSAGE/TITLE/DESCRIPTION/MESSAGE_IS_TRUNCATED/TIMESTAMP/AUTHOR. MR: IID placeholder 1, SOURCE/TARGET_BRANCH_NAME, EVENT_TYPE detached, SOURCE/TARGET_BRANCH_SHA '' (upstream: empty in detached MR pipelines), PROJECT_PATH, SOURCE_PROJECT_PATH. Omitted list documented in the module.
5. Per-job vars move from filter_jobs_by_rules into PredefinedVariables.job_variables, below root+CLI vars (upstream seed order).
6. IncludeProcessor: default_branch from its variables, not ENV.
7. Pins: PinnedPipelineContext + generate_output_references.sh pin --ref main (+ DEFAULT_BRANCH/SHA vars); CI_COMMIT_BRANCH/TAG/REF pins dropped, so 'unset' is expressed by the ref kind.
8. Drift spec against predefined_variables.md; specs red on parent; e2e-update reviewed.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in 7a4b351. PredefinedVariables = read_git (only I/O, facts or nil) + pure derivation (pipeline_variables, job_variables, resolve_ref, project_path_from_remote, slugify, group_name, canonical_source). Context gains ref; pipeline_source is canonical upstream (aliases merge_request->merge_request_event, manual->web mapped in Context.from_options; kept so existing users do not break). --ref: BRANCH|TAG|refs/heads/X|refs/tags/X, plain name = tag iff local tag exists, both = 'Ref is ambiguous'; default = checked-out branch, detached at exactly one tag = tag pipeline, otherwise ref vars unset. MR pipeline needs a branch (RefError otherwise, reported by every command). No new CLI flags: MR IID is a documented placeholder 1, target = default branch, --variables overrides.
AC#1: parity specs (branch, tag, MR, alias, branch-with-open-MR; standard MR workflow incl. no tag pipeline) in dag/dry-run/export-just. AC#2: CI_COMMIT_BRANCH only branch pipelines, CI_COMMIT_TAG only tag pipelines, MR vars only MR; property-style spec over every source x ref kind x fact set: no '' except upstream's own (detached-MR SHAs, blank/one-line commit message/description). AC#3: drift spec (emitted names subset of predefined_variables.md; SOURCES == Enums::Ci::Pipeline.sources) and an omitted list with reasons in lib/predefined_variables.rb + README 'Predefined variables'.
Pins: PinnedPipelineContext and generate_output_references.sh now pin --ref refs/heads/main (an overlay cannot unset, so the ref kind expresses 'no CI_COMMIT_TAG') + CI_DEFAULT_BRANCH/SHA by value; PinnedPipelineContext.context(dir) helper for Context.new in specs. Verified load-bearing: in a detached worktree proj8 dag draws 1 job without the pin, 9 with it.
IncludeProcessor changes: default branch now from its variables (predefined+CLI), spec with a 3-branch repo where ENV and variable disagree.
Gates: 775/0/47 on main and in a detached worktree, just test exit 0, coverage 85.92/77.43; just e2e green with no golden change (all goldens are push/main; '' and unset are both falsy for the rules they use). Bite: 53/111 red on parent in the touched spec files (CLI parity ones behavioural); 5 mutants of core semantics killed.
Gotchas: (1) run_command/export_just_command copy options field by field and silently dropped :ref; fixed for ref, class filed as follow-up. (2) commit vars (message/author/timestamp) are git-derived and NOT pinned; no golden rule reads them today. (3) changes: still diffs HEAD vs merge-base(default branch) whatever --ref/source (TASK-25). (4) e2e covers only push pipelines; MR/tag behaviour is in parity specs only.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Predefined variables follow the pipeline type like GitLab: upstream source names (merge_request/manual kept as aliases), --ref selects branch vs tag, inapplicable variables are unset not empty, MR vars only in merge_request_event pipelines, CI/GITLAB_CI/CI_JOB_NAME_SLUG and derivable v19 additions added, CI_PROJECT_PATH from origin, omissions documented and drift-checked against predefined_variables.md. 7a4b351.
<!-- SECTION:FINAL_SUMMARY:END -->
