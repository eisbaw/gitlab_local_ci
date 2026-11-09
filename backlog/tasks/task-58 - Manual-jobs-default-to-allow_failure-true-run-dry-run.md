---
id: TASK-58
title: 'Manual jobs default to allow_failure: true (run, dry-run)'
status: To Do
assignee: []
created_date: '2026-11-09T22:39:00Z'
labels:
  - run
  - dry-run
  - correctness
dependencies: []
priority: low
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-22. Upstream: a when: manual job outside rules defaults to allow_failure: true (Entry::Job / Ci::Processable#allow_failure?), so a failing or unplayed manual job does not block later stages. MockJob takes allow_failure only from the config, so dry-run and run --run-deps treat a failed manual job as blocking. Check upstream semantics for manual jobs in rules (allow_failure false by default there) and apply in MockPipeline.build_mock_jobs.
<!-- SECTION:DESCRIPTION:END -->
