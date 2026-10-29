---
id: BLOG-4
title: Syntax highlighting palettes below AA on the new code backgrounds
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
code.css syntax colours predate the redesign. On the light parchment code background (--bg-soft #e8e1d2) several tokens fall well short of 4.5:1 (variable orange #e36209 ~2.7, keyword red #d73a49 ~3.5, green #22863a ~3.6, comments #6a737d ~3.7). In dark, comments #8b949e on the Nord code background are also under 4.5:1. Design one light and one dark syntax palette that fit the parchment/Nord themes and pass AA. Also: .markup.inline.raw references an undefined --color-code-bg.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every syntax token colour is >= 4.5:1 on its theme's code background (light and dark)
- [ ] #2 Palettes harmonise with parchment/slate (light) and Nord (dark)
- [ ] #3 Undefined --color-code-bg reference removed or defined
- [ ] #4 Checked visually on a post with code blocks in both themes (ui-review)
<!-- AC:END -->
