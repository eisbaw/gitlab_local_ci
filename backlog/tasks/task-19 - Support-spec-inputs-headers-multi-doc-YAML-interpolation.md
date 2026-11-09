---
id: TASK-19
title: Support spec:inputs headers, multi-doc YAML, $[[ ]] interpolation
status: To Do
assignee: []
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T17:55:00Z'
labels:
  - audit
  - include
  - feature
dependencies:
  - TASK-1
priority: high
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
YAML.safe_load keeps only the first document, so a file with a spec header drops all jobs and 'spec' becomes a job (lint: Job 'spec' must have script; dag empty). Breaks every CI component and any .gitlab-ci.yml with pipeline inputs. Inputs passed to a file without spec are silently ignored (upstream error 'Given inputs not defined in the spec section'). Upstream: Config::Yaml::Loader (MultiDocYaml, MAX_DOCUMENTS = 2), Header::* (spec, inputs, types/default/options/regex/description; new since v17.5: input rules, spec:include, spec:component), Interpolation::* (Access, Block MAX_FUNCTIONS = 3, functions expand_vars, truncate, posix_escape (new), split (new)). Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Header+document files load; spec validates inputs (type, default, options, regex)
- [ ] #2 $[[ inputs.x ]] and functions interpolated in included files and the root file (CLI --input)
- [ ] #3 Upstream interpolation error messages for missing/unknown inputs
<!-- AC:END -->
