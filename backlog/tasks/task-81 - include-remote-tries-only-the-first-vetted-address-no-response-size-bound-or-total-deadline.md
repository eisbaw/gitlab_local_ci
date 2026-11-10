---
id: TASK-81
title: >-
  include:remote: tries only the first vetted address; no response size bound or
  total deadline
status: To Do
assignee: []
created_date: '2026-11-10T11:30:00Z'
labels:
  - include
  - reliability
dependencies: []
priority: medium
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-74 architecture review. public_address_of returns the first address and Net::HTTP pins it; if that address is unreachable (e.g. an IPv6 AAAA on an IPv4-only host) the fetch fails without trying the other vetted addresses. Also no include fetch (remote, project, component, template) bounds the response size, and the read timeout is per read, not a total deadline, so a slow-drip server can hold the tool. Decide: bounded fallback across vetted addresses; a byte cap; an overall deadline.
<!-- SECTION:DESCRIPTION:END -->
