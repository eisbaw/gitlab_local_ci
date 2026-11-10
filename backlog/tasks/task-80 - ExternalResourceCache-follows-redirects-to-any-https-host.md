---
id: TASK-80
title: ExternalResourceCache follows redirects to any https host
status: To Do
assignee: []
created_date: '2026-11-10T11:16:00Z'
updated_date: '2026-11-10T11:44:00Z'
labels:
  - include
  - security
dependencies: []
priority: low
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in TASK-75. download_file follows up to 5 redirects to any https:// host. For include:project the instance may redirect elsewhere (sign-in, object storage); the request carries no credentials, so the exposure is the project path in the URL. Decide whether a redirect may leave the instance's host, and spec it. Also: a cached project file for a branch ref (default 'master') is served forever; consider whether the cache should key only immutable refs (SHAs, tags) or expire.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Redirect part DONE in the review fix-round commit (fix(include): address-check every download hop): every redirect hop of a project/component/template download is now address-checked and pinned (PublicAddress) before connecting; only the user's instance (same host and port) is exempt, so a redirect away from it to a private address is refused. Policy chosen: a redirect may leave the instance, but only to public addresses (it carries no credentials; the exposure is the project path in the URL). Still OPEN here: cached files for branch refs (default 'master') are served forever; decide on keying only immutable refs or expiring.
<!-- SECTION:NOTES:END -->
