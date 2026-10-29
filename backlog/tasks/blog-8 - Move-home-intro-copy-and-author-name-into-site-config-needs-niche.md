---
id: BLOG-8
title: Move home intro copy and author name into site config (needs niche)
status: To Do
assignee: []
created_date: '2026-10-29T22:09:00Z'
labels:
  - theme
  - niche
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The home headline ('Engineering notes, from the schematic to the type system.'), byline name and 'Compilers · embedded · Linux · agents' are hard-coded in index.html; the footer name is hard-coded in base.html while site-config.nix has author.name = 'eisbaw'. Moving them to config needs niche to pass extra site fields to templates. niche's SiteConfig silently drops unknown keys (no deny_unknown_fields), and NavItem ignores external = true the same way, so a new key would vanish without error. Fix that in niche first (fail fast on unknown keys, or an explicit extra map), then read the copy from config.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 niche rejects or explicitly passes through unknown site-config keys (no silent drop)
- [ ] #2 Home intro and footer name come from site-config.nix
- [ ] #3 just e2e passes
<!-- AC:END -->
