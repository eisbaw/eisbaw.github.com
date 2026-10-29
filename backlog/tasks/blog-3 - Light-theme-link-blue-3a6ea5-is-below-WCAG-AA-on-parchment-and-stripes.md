---
id: BLOG-3
title: 'Light theme: link blue #3a6ea5 is below WCAG AA on parchment and stripes'
status: To Do
assignee: []
created_date: '2026-10-29T22:09:00Z'
labels:
  - theme
  - a11y
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Text accent --accent (#3a6ea5, the logo blue) measures 4.43:1 on --bg #f0eadd, ~4.04:1 on --stripe #e6e0d2 and ~4.08:1 on --bg-soft (current sidebar link). Normal-size text needs 4.5:1. Affected: archive links, links inside striped table rows, .top-nav current item, .sidebar-list current link. Kept as #3a6ea5 by choice when the theme was adopted; this task records the decision point. Option: a text-only accent such as #346496 (5.14 on bg, 4.68 on stripes) while the logo and sprites keep #3a6ea5.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision recorded: keep #3a6ea5 for text, or introduce a separate text accent
- [ ] #2 If changed: every accent-on-surface text pair in the light palette is >= 4.5:1 (bg, card, soft, stripe)
- [ ] #3 Logo and sprite colours unchanged
<!-- AC:END -->
