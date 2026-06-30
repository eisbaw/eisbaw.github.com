# Project: blog.radix63.dk (eisbaw / niche static blog)

## Build & preview
- Build the site with `nix build` (or `just build`); output is the `./result` symlink.
- Serve locally with `just serve` (port 8099), which stops any prior server, rebuilds, then serves `./result`.

## Rendering / preview requests
- When asked to **render**, **preview**, or **show** a page in a browser, use `just preview <url>`.
  - It launches Brave with a throwaway profile and disk cache disabled, so the page is always fetched fresh (no stale cache/cookies/service-workers).
  - With no argument it opens the local server root; pass a full URL to target a specific page, e.g. `just preview http://127.0.0.1:8099/posts/<slug>/`.
  - `just serve` must be running first for localhost URLs.
