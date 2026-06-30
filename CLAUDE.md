# Project: blog.radix63.dk (eisbaw / niche static blog)

## Build & preview
- Build the site with `nix build` (or `just build`); output is the `./result` symlink.
- Serve locally with `just serve` (port 8099), which stops any prior server, rebuilds, then serves `./result`.

## Post title sprites (required)
- Every post should have an animated SVG sprite shown inline as a prefix to its title (on the post page and the index overview).
- Wire it up by setting `title_icon = "<file>.svg";` in the post's `meta.nix`, with the SVG living in that post's `assets/` dir. The templates render it via `.title-sprite` (sized to `1em`); posts without the field are simply unstyled.
- Style: 8-bit pixel-art sprite, on-topic for the post, in the site palette — Windows-2000 blue `#3a6ea5` + clay `#d97757` (plus light-blue/cream tints). Animate it with self-contained SMIL (no JS) so it still moves when embedded as an `<img>`; keep motion subtle and steppy (discrete, not smooth).
- New asset files are only picked up after `git add` — `nix build` reads the git tree, so an untracked sprite will not deploy.

## Rendering / preview requests
- When asked to **render**, **preview**, or **show** a page in a browser, use `just preview <url>`.
  - It launches Brave with a throwaway profile and disk cache disabled, so the page is always fetched fresh (no stale cache/cookies/service-workers).
  - With no argument it opens the local server root; pass a full URL to target a specific page, e.g. `just preview http://127.0.0.1:8099/posts/<slug>/`.
  - `just serve` must be running first for localhost URLs.
