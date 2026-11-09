---
id: TASK-31
title: >-
  extends: resolve like upstream Extendable over every key (hidden roots, key
  order, error texts)
status: To Do
assignee: []
created_date: '2026-11-09T18:41:00Z'
updated_date: '2026-11-09T19:23:00Z'
labels:
  - audit
  - config
dependencies: []
priority: high
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing TASK-6. Upstream Extendable iterates every top-level key (Extendable#each) and extends any Hash with :extends. Ours (ExtendsResolver#resolve_extends) only resolves non-hidden, non-reserved jobs: (1) a hidden template chain deeper than 11 that no job uses errors upstream ('nesting too deep') but passes ours; hidden templates are left unresolved in our output. (2) resolve_extends rebuilds the hash as config.reject(jobs).merge(resolved_jobs), moving every job after templates/globals; upstream keeps key order (observable in lint jobs list and dry-run dispatch order). (3) Unknown-parent and circular messages differ from upstream ('<key>: unknown keys in `extends` (...)', '<key>: circular dependency detected in `extends`'); a non-Hash base is reported as 'not defined' instead of 'invalid base hashes'. Ref gitlab/lib/gitlab/ci/config/extendable{,/entry}.rb at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Hidden templates resolved and depth/circular checks applied from every key, matching upstream
- [ ] #2 Key order preserved through extends resolution (goldens reviewed)
- [ ] #3 Error texts match upstream; specs for each
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From architect review of TASK-5/6 (GO): (1) BLOCKS TASK-8 - upstream Extendable extend!s every key incl. hidden templates and writes results back before Tags::Resolver, so !reference [.tpl, script] sees .tpl post-extends; resolve all roots (with a memo hash, fixes fan-out^depth too) so circular/nesting errors in unused templates are also raised. (2) Then delete lint_command.rb#validate_extends (second source of truth; only sees hidden templates) and surface resolver errors. (4) resolve_extends rebuilds the hash with reject+merge, moving jobs after templates/globals; upstream keeps positions (@context[key] = merged) - matters since dry-run schedules in key order. (5) error texts for unknown parent / circular differ from upstream.

Forward-carried from TASK-4: extends runs in exactly one place, PipelineBuilder.resolve_config (lib/pipeline_builder.rb), after process_includes and before anything reads jobs; every subcommand (lint, dag, dry-run, run, export-just) gets its config from there. Plug in: change ExtendsResolver#resolve_extends (lib/extends_resolver.rb) to resolve every CiKeywords.job_entry? key, hidden ones included (memoised), writing each result back in place. AC#2 (key order) is DONE in 16e9c82: the result is config.to_h { |k, v| [k, resolved.fetch(k, v)] }; keep that. Errors: raise from the resolver; resolve_config turns them into Result#errors as "Error resolving extends: <msg>" (one print per command). If you switch to upstream texts, update that prefix there, not per command. Then delete LintCommand#validate_extends (second source of truth). The goldens pin lint.json job order for proj12/proj20 after 16e9c82.
<!-- SECTION:NOTES:END -->
