Stale files kept for reference, not used by any recipe or test.

- setup_submodules.sh: one-off that force-removed and re-added submodules
  (mastodon, grafana, ...) that never made it into .gitmodules.
- external_projects_harness/: network-based harness that curled unpinned
  master .gitlab-ci.yml files and ran lint/dag/dry-run on them, plus its
  justfile recipes (patch) and an Oct 2025 results summary. Superseded by
  the pinned external_projects/ submodules.
- demo.gitlab-ci.yml: former root demo config; just lint/dag/dry-run now
  default to test_ci_projects/proj1.
