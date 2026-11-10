---
id: TASK-75
title: >-
  include:project leaks private project paths to gitlab.gnome.org and
  gitlab.freedesktop.org
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T10:14:00Z'
updated_date: '2026-11-10T11:16:00Z'
labels:
  - audit
  - security
  - include
dependencies: []
priority: high
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From docs fact-check: ExternalResourceCache fetch_project_file tries KNOWN_GITLAB_INSTANCES (gitlab.com, gitlab.gnome.org, gitlab.freedesktop.org) in turn, so a private project path is sent to unrelated hosts. Upstream resolves project includes on the instance that runs the pipeline. Use one configured host (CI_SERVER_URL / --variables or derived from the origin remote), never a fan-out. Also: try_fetch_local_project_file reads ../<project>/<file> and ignores ref - document or honour ref. SECURITY.md documents current behaviour.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 include:project fetches from exactly one host: --variables CI_SERVER_URL, else origin remote host, else https://gitlab.com; no fan-out
- [x] #2 Host derivation reuses the one origin parser (PredefinedVariables.parse_remote behind project_path_from_remote and server_url_from_remote)
- [x] #3 A failed fetch names the chosen instance and how it is chosen
- [x] #4 Decision recorded for components, templates and the sibling ../<project> shortcut
- [x] #5 Specs with stubbed HTTP assert exactly one host and which, for CI_SERVER_URL, origin, and neither
- [x] #6 SECURITY.md Network, docs/usage.md and CHANGELOG updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PredefinedVariables: one remote parser (parse_remote) behind project_path_from_remote and a new server_url_from_remote; server_url(project_dir:, variables:) = --variables CI_SERVER_URL, else origin host (https), else https://gitlab.com. 2. PipelineBuilder passes that to IncludeProcessor; ExternalResourceCache.fetch_project_file(project, file, ref:, server_url:) fetches from that one instance only, cache keyed by instance; error names the instance and how to change it. KNOWN_GITLAB_INSTANCES removed. 3. Components keep their own fqdn; templates keep gitlab.com fallback (public content). 4. Sibling ../<project> shortcut kept, warns once per project that ref is not honoured; its blanket rescue removed (a read error no longer silently falls through to the network). 5. Specs: stubbed HTTP, exactly one host per case (CLI var, origin, neither). Docs.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decisions. Components: unchanged, fetched from the fqdn in the reference (the config names the host, so no path goes to an unrelated host). Upstream accepts only components on its own fqdn; parity filed as TASK-79. $CI_SERVER_FQDN in a component path follows the instance (TASK-78). Templates: unchanged, gitlab/ checkout then gitlab.com; template paths are public, nothing private leaks. Sibling shortcut: kept, not ref-aware. It exists for editing an included project locally next to this one, which git show <ref>:<file> would defeat, and it would fail for refs never fetched there. It now warns once per project that ref is not honoured, and its blanket 'rescue StandardError -> nil' is gone: a read error used to fall through to a network request silently. Extra: ref containing '..' rejected (cache path component; invalid git ref anyway); CI_SERVER_URL path with '..' rejected. Cache is now keyed per instance (ext_tmp/projects/<host[:port][/root]>/...), since one project path on two instances is two projects; old entries are orphaned and refetched. Bite: against the parent lib, the 4 PipelineBuilder-level specs (CI_SERVER_URL, origin, fallback+404 no fan-out, error names instance) are red; the cache-level specs are red too but partly only from the changed signature. Manual: lint of external_projects/mesa (origin gitlab.freedesktop.org) from a scratch cwd fetched freedesktop/ci-templates and gfx-ci/ci-tron from gitlab.freedesktop.org only, cached under ext_tmp/projects/gitlab.freedesktop.org/. Limits: a repo whose origin is not GitLab (this repo: github.com) derives that host; pass CI_SERVER_URL. A GitLab under a relative URL root cannot be derived from origin (pre-existing for CI_PROJECT_PATH too). Follow-up TASK-80: redirects may leave the instance; branch refs cached forever.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
include:project asks exactly one GitLab instance (--variables CI_SERVER_URL, else origin host via the shared remote parser, else gitlab.com), cache keyed per instance, error names the instance. Sibling checkout shortcut kept with a once-per-project 'ref not honoured' warning and no longer swallows read errors. Components/templates unchanged (rationale in notes; parity follow-up TASK-79).
<!-- SECTION:FINAL_SUMMARY:END -->
