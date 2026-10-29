---
id: BLOG-11
title: 'Home page: ''Threads'' section for posts that belong together'
status: To Do
assignee: []
created_date: '2026-10-29T22:09:00Z'
labels:
  - theme
  - feature
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The adopted mockup had a Threads row (e.g. the two desktop-latency posts, the two 'my stack' posts, the three Cinematic Documentation versions). niche has no series data, so it was left out. niche already passes extra meta.nix fields through to templates, so a 'series' field per post could drive it: group posts_index by series in index.html and render one compact card per series (sprite square, title, post count).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A meta.nix field groups posts into a series
- [ ] #2 Home page shows a Threads row for series with 2+ posts, styled with the existing panel tokens
- [ ] #3 Post pages link to the other posts in their series
<!-- AC:END -->
