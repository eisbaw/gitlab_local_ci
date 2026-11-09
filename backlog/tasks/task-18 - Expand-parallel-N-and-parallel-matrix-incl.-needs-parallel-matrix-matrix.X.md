---
id: TASK-18
title: >-
  Expand parallel: N and parallel:matrix (incl. needs:parallel:matrix, $[[
  matrix.X ]])
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T17:54:00Z'
updated_date: '2026-11-09T23:00:00Z'
labels:
  - audit
  - config
  - feature
  - good-enough
dependencies:
  - TASK-1
priority: medium
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Not expanded at all: matrix jobs keep original name and vanish from dry-run. Upstream Config::Normalizer creates 'job 1/2' and 'job: [aws, x]' names, injects matrix vars, rewrites needs/dependencies; needs:parallel:matrix selects instances; MatrixInterpolator ($[[ matrix.X ]] in needs) is new since v17.5. Upstream ref: gitlab/ submodule at v19.5.3-ee.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Job names and variables match upstream Normalizer for parallel N and matrix
- [x] #2 needs/dependencies on a parallel job fan out; needs:parallel:matrix selects
- [x] #3 dag, dry-run, run, export-just all show expanded jobs
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Study upstream Normalizer (NumberStrategy/MatrixStrategy), MatrixInterpolator, Entry::Product validation, CI_NODE_* semantics. 2. Add expansion step in PipelineBuilder at the upstream position (after flatten/defaults, before stages/rules) with upstream names, matrix vars in job variables, parallel metadata for CI_NODE_*. 3. needs/dependencies fan-out, needs:parallel:matrix selection, $[[ matrix.X ]] interpolation. 4. Validation errors with upstream wording. 5. Wire lint/dag/dry-run/run/export-just; run base-name -> error listing instances; export-just sanitized recipe names. 6. Specs bite red/green, e2e goldens reviewed, corpus check.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Forward-carried from TASK-10 (7a4b351): CI_NODE_INDEX/CI_NODE_TOTAL were deliberately left out of PredefinedVariables.job_variables because parallel jobs are not expanded yet. When expanding: upstream predefined_variables_from_job_attr sets CI_NODE_TOTAL for every job (Gitlab::Utils::Job.node_total: parallel total, else 1) and CI_NODE_INDEX only for an instance (options[:instance]); add both to job_variables (name: is then the expanded name, e.g. 'rspec 1/3' or 'build: [aws]', and CI_JOB_GROUP_NAME already strips that suffix via PARALLEL_VARIANT_REGEX). Rules of an expanded job see its matrix variables (rules on $PROVIDER, audit_vars/r3 matrix_job).

Forwarded from TASK-22 (79ef1d8): run and export-just take a job's variables from JobEnvironment.build (lib/job_environment.rb), which reads job['variables'] of Result#pipeline_jobs and PipelineBuilder.job_predefined_variables(name, job). Matrix variables must be injected into the expanded job's 'variables' (as upstream Normalizer does, so they rank as job yaml variables) and CI_NODE_INDEX/CI_NODE_TOTAL added in job_predefined_variables/PredefinedVariables.job_variables - then run, export-just and rules all see them with no change to JobEnvironment. Add a JobEnvironment spec for a matrix instance.

Done in e6c79b7 (expansion, names, variables, CI_NODE_*, validation, rules see job variables), d0c660c (needs/dependencies fan-out, needs:parallel:matrix, $[[ matrix.X ]]), e4ee27f (run naming, export-just recipe names, README). Seam: PipelineBuilder.expand_parallel -> lib/parallel_expander.rb, after compose_jobs and before stage_errors/rules (upstream Config#normalized_jobs). Instance = job with matrix variables merged over its variables: and parallel: {instance, total}; PipelineBuilder.parallel_instance/job_predefined_variables derive CI_NODE_*. MockServer#create_pipeline calls the same step.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
parallel: N and parallel:matrix expand in PipelineBuilder at upstream's position (composed jobs, before stage check and rules), so lint/dag/dry-run/run/export-just all see instances named exactly as upstream ('job 1/3', 'job: [a, b]', key order, entry order). Matrix vars rank as job variables (rules:variables and CLI win); CI_NODE_INDEX for instances, CI_NODE_TOTAL for every job. needs/dependencies fan out; needs:parallel:matrix and $[[ matrix.X ]] select instances; Entry::Product validation with upstream texts. Rules now see job variables (TASK-11 AC#1). run refuses a base name and lists instances; export-just recipe names collapse special-char runs and suffix collisions -2, -3. gitlab-runner corpus lint now valid (222 jobs). Divergences: $[[ matrix.X ]] resolves only matrix variables (upstream also job variables, as garbage text); expanded need-name length (255) not checked; dag tooltip shows parallel: {instance,total}. Follow-up: TASK-59 (DOT id collisions).
<!-- SECTION:FINAL_SUMMARY:END -->
