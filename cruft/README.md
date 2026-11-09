Stale files kept for reference, not used by any recipe or test.

- setup_submodules.sh: one-off that force-removed and re-added submodules
  (mastodon, grafana, ...) that never made it into .gitmodules.
- external_projects_harness/: network-based harness that curled unpinned
  master .gitlab-ci.yml files and ran lint/dag/dry-run on them, plus its
  justfile recipes (patch) and an Oct 2025 results summary. Superseded by
  the pinned external_projects/ submodules.
- demo.gitlab-ci.yml: former root demo config; just lint/dag/dry-run now
  default to test_ci_projects/proj1.
- docs-2025/: the 2025 documentation set, superseded by the README rewrite.
  README.md (the old README; every line is either carried into README.md /
  docs/ or listed as dropped in the commit that moved it), TODO.md and
  todo-checklist.md (duplicated backlog/), COVERAGE_REPORT.md (Oct 2025
  snapshot), lib-commands-README.md (describes the old gem-based design),
  and docs that described unbuilt or changed behaviour: api_reference,
  architecture, event_schema, privacy, release_checklist, runner_format,
  upgrade_guide (its unreleased notes moved to CHANGELOG.md), versioning,
  SECURITY.md (fabricated version table and contact).
