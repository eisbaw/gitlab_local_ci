---
id: TASK-78
title: >-
  include: host CI_SERVER_* environment variables leak into include path
  expansion
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T10:29:00Z'
updated_date: '2026-11-10T11:21:00Z'
labels:
  - include
  - variables
dependencies: []
priority: low
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-56. IncludeProcessor#expand_ci_variables reads ENV['CI_SERVER_FQDN'], ENV['CI_SERVER_HOST'], ENV['CI_SERVER_URL'] (falling back to gitlab.com) when expanding include:project/component paths. Rules and job variables never see host env (verified in TASK-56: grep ENV over lib/ hits only include_processor), but includes do: running inside a real CI job on a self-hosted instance silently resolves components against that instance. Decide: take these from the simulated predefined variables / --variables only, or document it as a deliberate knob (and then not under CI_* names). (GITLAB_CI_ALLOWED_DOMAINS, also read there, is documented in SECURITY.md.)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 $CI_SERVER_URL/_HOST/_FQDN in include paths come from the builder's variable set (--variables) or the instance TASK-75 picks, never from ENV
- [x] #2 CI_SERVER_URL in include expansion agrees with the include:project host (same server_url)
- [x] #3 Spec: host CI_SERVER_* in the spawned CLI's env does not change the result
- [x] #4 Other ENV reads in lib/ fixed or listed
- [x] #5 SECURITY.md, docs/usage.md, CHANGELOG updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. expand_ci_variables: CI_SERVER_URL from the builder's server_url (= --variables CI_SERVER_URL, else origin, else gitlab.com: TASK-75's choice), CI_SERVER_HOST/FQDN from --variables if set, else derived from that URL (FQDN with a non-default port, as upstream). No ENV. 2. Audit ENV reads in lib/. 3. CLI-level spec: host CI_SERVER_* in the spawned CLI env does not change the component host. 4. Docs/CHANGELOG.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision: taken from --variables / the derived instance, not kept as a knob. HOST and FQDN default to the server_url's host and host[:non-default port] (upstream: CI_SERVER_FQDN carries the port), --variables wins per name. Expansion now uses one regex with a word boundary, so $CI_SERVER_HOSTX is no longer half-expanded. Remaining ENV reads in lib/ (grep 'ENV' lib bin): include_processor GITLAB_CI_ALLOWED_DOMAINS (tool knob, not a simulated value, documented in SECURITY.md); run_command HostEnvironment.select(ENV.to_h, ...) (job environment base, by design, TASK-56). Implicit: Net::HTTP honours https_proxy/no_proxy; git subprocesses honour GIT_DIR etc. (a GIT_DIR in the host env could redirect what PredefinedVariables reads; not fixed, documented in SECURITY.md as git's own variables). Bite: spec/integration/include_host_env_spec.rb, 6/6 red against the parent's include_processor.rb. The CLI spec cuts the network with https_proxy=http://127.0.0.1:9 and a pre-seeded component cache, so neither the pass nor the parent's failure leaves the machine.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Include-path $CI_SERVER_* now come from --variables or the instance include:project uses (TASK-75), never from the tool's environment; FQDN derived with the port as upstream. ENV audit: only GITLAB_CI_ALLOWED_DOMAINS (tool knob) and the run job-environment base remain.
<!-- SECTION:FINAL_SUMMARY:END -->
