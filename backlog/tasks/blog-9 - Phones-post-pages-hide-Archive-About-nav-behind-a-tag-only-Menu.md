---
id: BLOG-9
title: 'Phones: post pages hide Archive/About nav behind a tag-only Menu'
status: To Do
assignee: []
created_date: '2026-10-29T22:09:00Z'
labels:
  - theme
  - mobile
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Below 880px, .top-nav is hidden and the Menu button opens the tag sidebar, which contains only tags and posts, not the site nav (Home, Archive, About, Colophon, Source). On post, archive and tag pages a phone reader cannot reach those links except via the logo. The home page avoids this (.no-sidebar keeps the nav visible). Predates the redesign. Options: put the nav links at the top of the mobile sidebar, or keep a compact nav row on phones everywhere.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every site nav link is reachable on a 390px viewport from post, archive and tag pages
- [ ] #2 Header stays compact enough on phones (check with ui-review)
<!-- AC:END -->
