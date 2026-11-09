---
id: TASK-31
title: >-
  extends: resolve like upstream Extendable over every key (hidden roots, key
  order, error texts)
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T18:41:00Z'
updated_date: '2026-11-09T19:51:00Z'
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
- [x] #1 Hidden templates resolved and depth/circular checks applied from every key, matching upstream
- [x] #2 Key order preserved through extends resolution (goldens reviewed)
- [x] #3 Error texts match upstream; specs for each
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1) ExtendsResolver: extend! every top-level key (upstream Extendable#each), hidden roots included, memoised by key with chain height so the nesting check stays exact under memo; write back in place (keep 16e9c82 order). 2) Upstream error texts verbatim (unknown keys / invalid base hashes / nesting too deep / circular dependency); drop the 'Error resolving extends:' prefix in resolve_config since upstream texts name the key and keyword. 3) Delete LintCommand#validate_extends. 4) Specs: unused circular pair, unused 12-chain, each error text, memo fan-out bound, via lint.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
From architect review of TASK-5/6 (GO): (1) BLOCKS TASK-8 - upstream Extendable extend!s every key incl. hidden templates and writes results back before Tags::Resolver, so !reference [.tpl, script] sees .tpl post-extends; resolve all roots (with a memo hash, fixes fan-out^depth too) so circular/nesting errors in unused templates are also raised. (2) Then delete lint_command.rb#validate_extends (second source of truth; only sees hidden templates) and surface resolver errors. (4) resolve_extends rebuilds the hash with reject+merge, moving jobs after templates/globals; upstream keeps positions (@context[key] = merged) - matters since dry-run schedules in key order. (5) error texts for unknown parent / circular differ from upstream.

Forward-carried from TASK-4: extends runs in exactly one place, PipelineBuilder.resolve_config (lib/pipeline_builder.rb), after process_includes and before anything reads jobs; every subcommand (lint, dag, dry-run, run, export-just) gets its config from there. Plug in: change ExtendsResolver#resolve_extends (lib/extends_resolver.rb) to resolve every CiKeywords.job_entry? key, hidden ones included (memoised), writing each result back in place. AC#2 (key order) is DONE in 16e9c82: the result is config.to_h { |k, v| [k, resolved.fetch(k, v)] }; keep that. Errors: raise from the resolver; resolve_config turns them into Result#errors as "Error resolving extends: <msg>" (one print per command). If you switch to upstream texts, update that prefix there, not per command. Then delete LintCommand#validate_extends (second source of truth). The goldens pin lint.json job order for proj12/proj20 after 16e9c82.

Implemented in 775abb7. ExtendsResolver walks EVERY top-level key as a root (upstream Extendable#each; not only CiKeywords.job_entry? keys, so e.g. a Hash under default: with extends: is extended too, as upstream does), memoised per key with the chain height, so a template already resolved as its own root is re-walked when reached deeper and the nesting error names the same entry upstream's walk names (spec 'memoisation'). Diamond of 10 levels went from 2^10 merges to linear (spec bounds deep_merge calls). Error texts verbatim in upstream order: '<key>: unknown keys in `extends` (a, b)', '<key>: invalid base hashes in `extends` (a)', '<key>: nesting too deep in `extends`', '<key>: circular dependency detected in `extends`'. resolve_config reports them without the old 'Error resolving extends: ' prefix and rescues only ExtendsResolver::ExtensionError. LintCommand#validate_extends deleted. AC#2 was already done by 16e9c82 (config.to_h { |k, v| [k, resolved.fetch(k, v)] }), verified by its spec, kept. Deliberate difference: the 'extends' key is removed from merged entries (upstream keeps it in the hash; no job value exposes it). Bite: spec/unit/extends_resolver_spec.rb on parent f66d648: 23 examples, 12 failures; on 775abb7: 23/0. Suite 589/0/47 on main and in a detached worktree; e2e green, no golden change. Cross-task spec (!reference sees a template's extended result) landed with TASK-8 in cca6a10 ('sees the extended result of a template'). Lesson: in a detached worktree, git checkout --detach <rev> replaces the gitlab symlink with the empty submodule dir again; re-link after every checkout or the CiKeywords drift specs silently skip (49 pending instead of 47).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ExtendsResolver resolves every top-level key like upstream Extendable (hidden and unused templates included), memoised with exact nesting semantics, upstream error texts and check order; lint surfaces the resolver's errors and its duplicate validate_extends is gone. Commit 775abb7; 589/0/47 main and detached; e2e green, no golden change.
<!-- SECTION:FINAL_SUMMARY:END -->
