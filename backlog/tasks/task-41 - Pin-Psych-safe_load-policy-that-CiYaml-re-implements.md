---
id: TASK-41
title: Pin Psych safe_load policy that CiYaml re-implements
status: To Do
assignee: []
created_date: '2026-11-09T19:57:00Z'
labels:
  - audit
  - hardening
dependencies: []
priority: low
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lib/ci_yaml.rb uses private Psych register, ClassLoader::Restricted, ScalarScanner(strict_integer:). If Psych hardens safe_load defaults/limits CiYaml silently won't inherit them; differential spec checks values, not policy. Add a spec pinning Psych.method(:safe_load).parameters and Psych::VERSION major so upgrades force a re-read.
<!-- SECTION:DESCRIPTION:END -->
