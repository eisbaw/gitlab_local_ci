---
id: TASK-30
title: >-
  Dev shell: nixpkgs ruby_3_3 bundled gems print 'extensions are not built' on
  gem scan
status: To Do
assignee: []
created_date: '2026-11-09T18:12:00Z'
labels:
  - tooling
  - nix
dependencies: []
priority: low
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In the flake dev shell, any require that makes RubyGems scan all specs (bare require of a bundled gem such as rexml, require 'gitlab' via lib/runner_exporter.rb, require 'bundler/setup') prints 'Ignoring debug-1.9.2/racc-1.7.3/rbs-3.4.0 because its extensions are not built' to stderr: the store's lib/ruby/gems/3.3.0/extensions/ is empty. TASK-1 mitigated only the lint --format junit path (gem 'rexml' in lib/formatters/junit_formatter.rb) because it leaked into goldens. Fix the class in flake.nix/shell.nix (e.g. provide the gem set via bundlerEnv / ruby.withPackages, or a ruby build with bundled-gem extensions); unverified which works. Then the gem 'rexml' line can go. just e2e captures stderr per command, so a regression shows up there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No 'extensions are not built' line from any CLI subcommand or rspec in the dev shell
- [ ] #2 gem 'rexml' mitigation removed or justified
<!-- AC:END -->
