---
id: TASK-79
title: >-
  include: component on a host other than the instance is fetched, upstream
  rejects it
status: To Do
assignee: []
created_date: '2026-11-10T11:16:00Z'
updated_date: '2026-11-10T11:44:00Z'
labels:
  - include
  - parity
dependencies: []
priority: low
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-75. Upstream Components::InstancePath.match? only treats an include as a component when it starts with "#{Gitlab.config.gitlab.server_fqdn}/" (gitlab/lib/gitlab/ci/components/instance_path.rb); a component on another host is not a component include and the pipeline fails. This tool fetches from whatever fqdn the reference names. Decide: reject components whose fqdn differs from the instance (PredefinedVariables.server_url host[:port]) for parity, with an error naming both; consider what that means for users with no origin (gitlab.com fallback) using components from other instances.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Related, from the review fix round: a component host is now address-checked (non-public refused) unless it equals the user's instance (CI_SERVER_URL / origin host), same host and port. That closes the SSRF part (component: 127.0.0.1:18443/... used to connect). This task's parity question remains: upstream rejects any component not on the instance's fqdn; we still fetch public foreign hosts.
<!-- SECTION:NOTES:END -->
