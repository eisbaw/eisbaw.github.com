---
id: BLOG-7
title: 'Index pages 2+ never rendered: add heading and an e2e fixture'
status: To Do
assignee: []
created_date: '2026-10-29T22:09:00Z'
labels:
  - theme
  - test
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
posts_per_page is 20 and there are 19 posts, so the '{% else %}' branch of index.html (pages after the first: tile grid only) has never run. It renders no heading, and the 'Older posts' link in Earlier duplicates the pagination 'Older' link on page 1 once a page 2 exists. This activates at the 21st post. Add a page heading for pages 2+, drop the duplicate link, and cover the branch with an e2e fixture built with a small posts_per_page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pages 2+ have an h1 (may be visually hidden) and no duplicate navigation
- [ ] #2 e2e builds a fixture site with small posts_per_page and checks page 2 renders and links resolve
- [ ] #3 just e2e passes
<!-- AC:END -->
