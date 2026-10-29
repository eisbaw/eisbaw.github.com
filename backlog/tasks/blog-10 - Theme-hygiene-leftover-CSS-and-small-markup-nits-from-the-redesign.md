---
id: BLOG-10
title: 'Theme hygiene: leftover CSS and small markup nits from the redesign'
status: To Do
assignee: []
created_date: '2026-10-29T22:09:00Z'
labels:
  - theme
  - cleanup
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Small items from the redesign reviews: --radius-lg and --shadow-sm are now unused, and .post-summary still declares the 'icon' grid area that no template uses; tile corner labels (.pl.tl tag vs .pl.tr date) have no collision guard above 560px, so a tag longer than 'reverse-engineering' will overlap the date; 'Archive ↗' uses an external-link arrow for an internal page; the 'Latest' heading and the 'Latest post' eyebrow repeat each other; truncate(length=7, end='') on dates could be date(format='%Y-%m'); code.css repeats [data-theme=dark] on every selector where one nesting block would do; header on phones grows to ~88px with the wrapped nav.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Unused tokens and dead grid areas removed
- [ ] #2 Tile labels cannot overlap at any width
- [ ] #3 Internal links use an internal arrow (or none)
- [ ] #4 Visual check in both themes, desktop and phone
<!-- AC:END -->
