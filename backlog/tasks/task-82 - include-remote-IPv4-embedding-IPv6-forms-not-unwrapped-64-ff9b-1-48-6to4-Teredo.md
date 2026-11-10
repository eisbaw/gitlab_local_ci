---
id: TASK-82
title: >-
  include:remote: IPv4-embedding IPv6 forms not unwrapped (64:ff9b:1::/48, 6to4,
  Teredo)
status: To Do
assignee: []
created_date: '2026-11-10T11:30:00Z'
labels:
  - include
  - security
dependencies: []
priority: low
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-74 review. embedded_ipv4 unwraps ::ffff:0:0/96, ::/96 and 64:ff9b::/96 only. Local-use NAT64 64:ff9b:1::/48 (RFC 8215), 6to4 2002::/16 (IPv4 in bits 16..47) and Teredo 2001::/32 (obfuscated IPv4 server/client) are treated as plain public IPv6. Decide per form: unwrap and re-check, or refuse wholesale; spec each.
<!-- SECTION:DESCRIPTION:END -->
