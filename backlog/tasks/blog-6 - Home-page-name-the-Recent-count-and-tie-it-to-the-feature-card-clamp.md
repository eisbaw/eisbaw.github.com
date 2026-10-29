---
id: BLOG-6
title: 'Home page: name the Recent count and tie it to the feature-card clamp'
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
index.html hard-codes the size of the Recent list three times (slice(start=1, end=4), posts | length > 4, slice(start=4)), and .feature-body p's -webkit-line-clamp: 5 is silently tuned to the height of those three rows. Use one {% set %} constant with a comment pointing at the clamp. Also move the blue/clay panel alternation out of the template (the tile macro uses 'i is odd -> blue', the Recent loop the opposite parity) into CSS nth-child rules, and replace .recent-row:nth-child(even), which depends on the bar being child 1, with an nth-of-type rule. Note that alternating by index gives vertical colour columns in an even-column grid; decide whether a checkerboard is wanted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Recent count defined once; changing it needs one edit
- [ ] #2 Panel tint alternation lives in CSS; the tile macro no longer takes an index
- [ ] #3 Stripe rule does not depend on DOM position of the bar
<!-- AC:END -->
