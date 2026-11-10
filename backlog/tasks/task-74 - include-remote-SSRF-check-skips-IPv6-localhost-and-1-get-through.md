---
id: TASK-74
title: 'include:remote SSRF check skips IPv6: localhost and ::1 get through'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-10T10:14:00Z'
updated_date: '2026-11-10T11:06:00Z'
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

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every resolved address (Resolv.getaddresses) is checked; any non-public one refuses the include
- [x] #2 IPv4 0/8,10/8,100.64/10,127/8,169.254/16,172.16/12,192.168/16 and IPv6 ::1, ::, fe80::/10, fc00::/7 refused; IPv4-mapped (and NAT64/compat) checked by the embedded IPv4
- [x] #3 Literal IP hosts checked the same way; a host with no address is an error
- [x] #4 Connection pinned to the vetted address (Net::HTTP ipaddr); Host/SNI/certificate check stay on the hostname
- [x] #5 Specs with stubbed resolver and HTTP, red on parent: localhost->::1, mixed public+private, ::ffff:127.0.0.1, fc00::1, 169.254.169.254 (+ fd00:ec2::254), [::1], public allowed
- [x] #6 SECURITY.md Network, docs/usage.md and CHANGELOG Security updated
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Resolve every address (Resolv.getaddresses); literal IP hosts (uri.hostname) skip DNS. 2. Refuse if any address is in an explicit non-public CIDR list (IPv4 and IPv6; IPv4-mapped/compat mapped back via IPAddr#native; NAT64/6to4 embedded IPv4 re-checked). No address -> error. 3. Pin the connect to the first vetted address (Net::HTTP ipaddr), so Host/SNI/cert check stay on the hostname and DNS rebinding between check and connect is closed. 4. Specs with stubbed resolver + Net::HTTP; red on parent. 5. SECURITY.md, docs/usage.md, CHANGELOG.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Bite: new spec/unit/include_remote_ssrf_spec.rb run against the parent's lib/include_processor.rb: 21 of 23 red. Green on parent, by design: 'allows public addresses' (regression guard) and 'resolves to nothing' (parent's getaddress also raised). The plain-IPv4 169.254.169.254 case alone was already refused on the parent; the example is red through its IPv6 half (fd00:ec2::254). [::1] was refused on the parent only by accident (Resolv.getaddress('[::1]') -> ResolvError, brackets). Pin verified outside the suite with a local TLS server (scratch script): Net::HTTP.start('ci.test', port, ipaddr: '127.0.0.1') sends Host ci.test and SNI ci.test, and a cert for other.test is refused (hostname still verified). Repro: lint of 'remote: https://localhost:9/x.yml' before = 'Failed to open TCP connection to localhost:9 (Connection refused)' (it connected); after = 'resolves to a non-public address (::1, 127.0.0.1)'. Limits: only the first vetted address is tried (no fallback to the next on connect failure); the allowlist is now checked before DNS.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
include:remote resolves every address, refuses any non-public one (IPv4 + IPv6, mapped/NAT64 forms by the embedded IPv4, literal IPs), errors on no address, and connects to the vetted address so DNS rebinding between check and connect is closed. Docs updated.
<!-- SECTION:FINAL_SUMMARY:END -->
