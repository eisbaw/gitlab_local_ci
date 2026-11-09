---
id: TASK-51
title: export-just emits invalid justfiles for multi-line script entries
status: To Do
assignee: []
created_date: '2026-11-09T21:19:00Z'
labels:
  - audit
  - export-just
dependencies: []
priority: medium
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-38 verification. export-just now runs on all 20 test projects, but just --evaluate rejects 3 of the 40 outputs (graph+flat): proj6 (heredoc 'cat > f << EOF' in test:unit: '<?xml' at column 1, 'unknown start of token'), proj7 (multi-line 'cat > Dockerfile' block: 'FROM alpine:3.19'), proj20 (block scalar: 'inconsistent leading whitespace'). Root cause: format_recipe writes each script entry as one recipe line ('    ' + entry), so a multi-line entry spills unindented lines into the justfile. Semantics are also off for single-line entries: just runs every recipe line in its own shell, GitLab runs the whole before_script+script in one shell (cd, exported vars, set -e persist). Likely fix: shebang recipes (#!/usr/bin/env bash, set -eo pipefail, entries verbatim, after_script separately) - an output-format decision, so review it as such. Verify with just --justfile <out> --evaluate on every test project (do not execute recipes).
<!-- SECTION:DESCRIPTION:END -->
