---
id: BLOG-5
title: 'Theme tokens: remove duplicate colour variables and fix flat text tiers'
status: To Do
assignee: []
created_date: '2026-10-29T22:09:00Z'
labels:
  - theme
  - refactor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In main.css, several tokens restate another token's value in both palettes: --ink-strong == --ink, --chip-ink == --bar-ink in light, chip-bg == accent in light. Define derived tokens once in :root as var() references and drop the dark copies. Separately, --ink / --ink-mute / --ink-faint are nearly identical (about 1.16:1 apart in light, 1.29:1 in dark), so secondary text no longer reads as secondary; either make the steps visible (keeping >= 4.5:1) or collapse to fewer tiers. Optionally express dark surfaces as color-mix(in srgb, var(--bg), var(--ink) N%) so the comment listing the mix percentages cannot rot.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No token in [data-theme=dark] merely repeats a value derivable from another token
- [ ] #2 Text tiers are either visibly distinct or reduced, all still >= 4.5:1
- [ ] #3 Visual check in both themes shows no regressions
<!-- AC:END -->
