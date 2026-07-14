# Project: blog.radix63.dk (eisbaw / niche static blog)

## Build & preview
- Build the site with `nix build` (or `just build`); output is the `./result` symlink.
- Serve locally with `just serve` (port 8099), which stops any prior server, rebuilds, then serves `./result`.

## Post title sprites (required)
- Every post should have an animated SVG sprite shown inline as a prefix to its title (on the post page and the index overview).
- Wire it up by setting `title_icon = "<file>.svg";` in the post's `meta.nix`, with the SVG living in that post's `assets/` dir. The templates render it via `.title-sprite` (sized to `1em`); posts without the field are simply unstyled.
- Style: 8-bit pixel-art sprite, on-topic for the post, in the site palette — Windows-2000 blue `#3a6ea5` + clay `#d97757` (plus light-blue/cream tints). Animate it with self-contained SMIL (no JS) so it still moves when embedded as an `<img>`; keep motion subtle and steppy (discrete, not smooth).
- New asset files are only picked up after `git add` — `nix build` reads the git tree, so an untracked sprite will not deploy.

## Inline glossary callouts
- Gloss a jargon term inline: it gets a dashed underline and a small `i` badge, and on hover or keyboard focus a card pops up with a definition (and an optional source link). Styles live in `theme/static/css/main.css` under the `.gloss` / `.gloss-card` / `.gc-*` selectors and reuse the theme tokens, so both light and dark themes are handled. Reveal is CSS-only (hover / `:focus-within`); a small script in `base.html` injects a close **×** into each card's `.gc-head` so a card pinned by a click/tap can be dismissed. Without JS the callouts still work (dismiss by clicking elsewhere).
- Author it as raw inline HTML in `post.md` (niche passes inline HTML through). Keep the whole thing on **one line** (a blank line inside breaks the Markdown HTML block). Pattern:
  - `<span class="gloss" tabindex="0">TERM<span class="gloss-card"><span class="gc-head"><span class="gc-name">Name</span></span><span class="gc-body">One or two plain sentences.</span><span class="gc-foot"><a href="URL" target="_blank" rel="noopener">host.tld</a></span></span></span>`
  - Drop the `<span class="gc-foot">…</span>` line for terms with no external source.
  - `tabindex="0"` makes the term keyboard-reachable (`:focus-within` opens the card). Do not hand-author a `gc-chip` or a close button; the close × is added by the theme.
- Intended usage: gloss anything a general engineer reader may not immediately know, **first occurrence only**, curated so it teaches without littering. Convention: named tools/products get a **source link** in the footer; plain concepts (idempotency, composition, cgroups) get a **definition only**. Do not gloss inside TL;DR bullets, headings, or the bolded lead.

## Rendering / preview requests
- When asked to **render**, **preview**, or **show** a page in a browser, use `just preview <url>`.
  - It launches Brave with a throwaway profile and disk cache disabled, so the page is always fetched fresh (no stale cache/cookies/service-workers).
  - With no argument it opens the local server root; pass a full URL to target a specific page, e.g. `just preview http://127.0.0.1:8099/posts/<slug>/`.
  - `just serve` must be running first for localhost URLs.
