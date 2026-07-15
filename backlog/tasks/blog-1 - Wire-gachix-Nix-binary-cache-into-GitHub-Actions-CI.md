---
id: BLOG-1
title: Wire gachix Nix binary cache into GitHub Actions CI
status: To Do
assignee: []
created_date: '2026-07-14 23:50'
labels:
  - ci
  - infra
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI (.github/workflows/deploy.yml) installs plain Nix and runs 'nix build .#default' against a cold /nix/store on every push, so all site derivations (niche engine, post-*, compiled-posts, site, blog) rebuild from scratch each time. Wire in gachix (eisbaw's git-repo-backed Nix binary cache) as a read-write pull-through cache so unchanged store paths are substituted, not rebuilt. Reference implementation: github.com/eisbaw/my_bin_cache_demo_gachix (.github/workflows/use-gachix-cache.yml).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Before 'nix build': fetch refs/heads/gachix/* into a bare cache repo (warm-started via actions/cache), run the gachix proxy (ghcr.io/eisbaw/gachix) on 127.0.0.1:8080, and configure Nix with extra-substituters + extra-trusted-public-keys
- [ ] #2 After 'nix build': sign and 'gachix add' newly-built paths on cache miss, then push refs/heads/gachix/* back
- [ ] #3 Own gachix signing keypair generated: public half in extra-trusted-public-keys, private half stored as GACHIX_SIGNING_KEY repo secret (do NOT reuse the demo's gachix-ci-1 key)
- [ ] #4 Cache-storage location decided: same repo (adds refs/heads/gachix/*) vs a dedicated cache repo (needs PAT/deploy key)
- [ ] #5 build job gets contents:write; deploy job keeps pages:write + id-token:write; a second push after cold-start shows cache hits and no rebuild of unchanged derivations
<!-- AC:END -->
