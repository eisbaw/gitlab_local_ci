---
id: TASK-74
title: 'include:remote SSRF check skips IPv6: localhost and ::1 get through'
status: To Do
assignee: []
created_date: '2026-11-10T10:14:00Z'
labels:
  - audit
  - security
dependencies: []
priority: high
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From docs fact-check 2026-11-10: validate_not_private_ip (lib/include_processor.rb) checks only the first address from Resolv.getaddress and only IPv4 ranges. 'remote: https://localhost:9/x.yml' resolved to ::1 and the tool connected. Check every resolved address (Resolv.getaddresses), cover IPv6 loopback/link-local/ULA (::1, fe80::/10, fc00::/7) and IPv4-mapped IPv6; SECURITY.md documents the current gap and must be updated with the fix.
<!-- SECTION:DESCRIPTION:END -->
